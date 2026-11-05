% =========================================================================
% STEP 2: GA + Hybrid FMINCON Optimization - PV_CC_ERM_NOpu fit to ADN
% =========================================================================
clearvars;

% --- 1. SÉCURITÉ WORKSPACE PRINCIPAL (Client) ---
disp('=== Chargement des variables (init_PV_CC_ERM.m) ===');
if exist('init_PV_CC_ERM.m', 'file')
    evalin('base', 'init_PV_CC_ERM;');
    disp('✔ Workspace principal initialisé (init_PV_CC_ERM.m).');
else
    warning('Le fichier init_PV_CC_ERM.m est introuvable.');
end

% --- AJOUT PATH : Dossiers nécessaires ---
wrapperDir = 'C:\Users\pcstudentgele11\Desktop\GeneticAlgorithm - Cyril Baudoux\6-GA_for_converter_association\Test_GA';
sweepDir = pwd; % Les 81 modèles balayés (NOpu) sont sauvegardés dans le dossier courant
if exist(wrapperDir, 'dir'), addpath(wrapperDir); else warning('Dossier wrapper introuvable.'); end
addpath(sweepDir);

% --- 2. Configuration & Loading Ground Truth ---
modelName      = 'PV_CC_ERM_NOpu';  
targetDataName = 'GT_ADN';   % <-- LA CIBLE COMPLEXE (ADN)

% Chargement intelligent du Ground Truth de l'ADN
if exist([targetDataName, '.mat'], 'file')
    temp = load([targetDataName, '.mat']); 
else
    % Va chercher dans le dossier ADN créé lors de la génération du GT
    gtFolder = fullfile(pwd, 'ADN'); 
    temp = load(fullfile(gtFolder, [targetDataName, '.mat']));
end

if isfield(temp, targetDataName)
    data_input = temp.(targetDataName);
elseif isfield(temp, 'GT_Combined')
    data_input = temp.GT_Combined;  
else
    data_input = temp.data_input;
end
scenarios = temp.scenarios;
t_eval_start    = 0.5;    
downsample_step = 100; 

% ---> SUFFIXE EXPLICITE POUR CE RUN <---
run_suffix      = '_on_ADN_Pop60_Gen100'; 

% =========================================================================
% 3. GENERIC MAPPING CONFIGURATION (18 Variables pour PV_CC_ERM)
% =========================================================================
opt_var_names = {'Ppv', 'wipv', 'wpllpv', 'wppv', 'wvpv', ...
                 'Pcc', 'Hcc', 'ksicc', 'wicc', 'wQSEMvcc', ...
                 'P_ERM', 'Q_ERM', 'Nps', 'Npt', 'Tp', 'Nqs', 'Nqt', 'Tq'};

% Limites Convertisseurs PV (1-5)
lb_pv = [0.01,   0.5,    0.5,    0.001,  0.002];
ub_pv = [0.99,   4000,   4000,   200,    100];

% Limites Convertisseurs CC (6-10)
lb_cc = [0.01,   0.001,  0.001,  0.5,    40];
ub_cc = [0.99,   10,     10,     4000,   90];

% Limites ERM (11-18) -> P_ERM, Q_ERM, Nps, Npt, Tp, Nqs, Nqt, Tq
lb_erm = [1000,   0,      0,      0,      0.01,   0,      0,      0.01];
ub_erm = [17000,  2000,   3,      3,      2.0,    3,      3,      2.0];

lb = [lb_pv, lb_cc, lb_erm];
ub = [ub_pv, ub_cc, ub_erm];
num_vars = length(opt_var_names);

% =========================================================================
% 4. SÉCURITÉ WORKERS PARALLÈLES
% =========================================================================
disp('Préparation du pool parallèle pour GA et FMINCON...');
pool = gcp(); 
parfevalOnAll(pool, @addpath, 0, sweepDir); 
parfevalOnAll(pool, @addpath, 0, wrapperDir); 
f = parfevalOnAll(pool, @evalin, 0, 'base', 'init_PV_CC_ERM'); % Sécurité Workers
wait(f); 
disp('✔ Workers parallèles initialisés avec init_PV_CC_ERM.m !');

% =========================================================================
% 5. Configuration GA et FMINCON (Hybride)
% =========================================================================
outputFcnHandle = @(options, state, flag) log_GA_Evolution_wrapper( ...
    options, state, flag, modelName, targetDataName, downsample_step);

% Configuration de FMINCON
hybridOpts = optimoptions('fmincon', ...
    'MaxIterations', 100, ...
    'MaxFunctionEvaluations', 300, ...
    'UseParallel', true, ... 
    'Display', 'iter');

% Configuration du GA (Restauré à Pop=60, Gen=100 pour le run final)
options = optimoptions('ga', ...
    'PopulationSize',    60, ...          
    'MaxGenerations',    100, ...          
    'CrossoverFraction', 0.75, ...
    'MaxStallGenerations', 8, ...      
    'FunctionTolerance', 1e-8, ...     
    'Display',           'iter', ...             
    'PlotFcn',           @gaplotbestf, ...       
    'UseParallel',       true, ...
    'HybridFcn',         {@fmincon, hybridOpts}, ... 
    'OutputFcn',         outputFcnHandle);

ObjectiveFunction = @(x) fitness_sweep_wrapper( ...
    x, data_input, scenarios, opt_var_names, downsample_step, t_eval_start, sweepDir, modelName);

% =========================================================================
% 6. EXÉCUTION DE L'ALGORITHME
% =========================================================================
disp('=========================================================');
disp([' Démarrage de l''optimisation globale : ', num2str(num_vars), ' variables']);
disp([' Optimisation du Modèle : [', modelName, '] sur Data : [', targetDataName, ']']);
disp([' Nom de sauvegarde    : [*', run_suffix, '*]']);
disp('=========================================================');

[x_opt, fval] = ga(ObjectiveFunction, num_vars, [], [], [], [], lb, ub, [], options);

% --- Sauvegarde du graphique de convergence avec suffixe ---
outputFolder = fullfile(pwd, modelName); 
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end
gaFig = gcf; 
figBaseName = fullfile(outputFolder, sprintf('Convergence_GA_%s_on_%s_ds%d%s_MSE', ...
    modelName, targetDataName, downsample_step, run_suffix));
savefig(gaFig, [figBaseName, '.fig']);
saveas(gaFig,  [figBaseName, '.png']);

% =========================================================================
% 7. Post-Optimization: Validation Finale avec x_opt (Raffiné)
% =========================================================================
disp('Calculating final MSE and MAE (Global and Detailed)...');

% Recherche du meilleur modèle initialisé (4D Grid)
idx_Ppv  = find(strcmp(opt_var_names, 'Ppv'));
idx_Pcc  = find(strcmp(opt_var_names, 'Pcc'));
idx_Perm = find(strcmp(opt_var_names, 'P_ERM'));
idx_Qerm = find(strcmp(opt_var_names, 'Q_ERM'));

grid_Ppv  = 0.25 : 0.25 : 0.75; 
grid_Pcc  = 0.25 : 0.25 : 0.75;
grid_Perm = 5000 : 4000 : 13000;
grid_Qerm = 100  : 700  : 1500;

[~, i1] = min(abs(grid_Ppv - x_opt(idx_Ppv)));   Ppv_disc  = grid_Ppv(i1);
[~, i2] = min(abs(grid_Pcc - x_opt(idx_Pcc)));   Pcc_disc  = grid_Pcc(i2);
[~, i3] = min(abs(grid_Perm - x_opt(idx_Perm))); Perm_disc = grid_Perm(i3);
[~, i4] = min(abs(grid_Qerm - x_opt(idx_Qerm))); Qerm_disc = grid_Qerm(i4);

strPpv  = strrep(sprintf('%.2f', Ppv_disc), '.', 'p');
strPcc  = strrep(sprintf('%.2f', Pcc_disc), '.', 'p');
strPerm = sprintf('%g', Perm_disc);
strQerm = sprintf('%g', Qerm_disc);

bestModelName = sprintf('%s_Ppv%s_Pcc%s_Pe%s_Qe%s', modelName, strPpv, strPcc, strPerm, strQerm);
fprintf('--> Modèle utilisé pour la vérification finale : %s.slx\n', bestModelName);
load_system(bestModelName);

num_runs = size(scenarios, 1);
for i = num_runs:-1:1
    simIn_opt(i) = Simulink.SimulationInput(bestModelName);
    for v = 1:num_vars
        simIn_opt(i) = simIn_opt(i).setVariable(opt_var_names{v}, x_opt(v), 'Workspace', bestModelName);
    end
    simIn_opt(i) = simIn_opt(i).setVariable('delta_E',         scenarios(i, 1));
    simIn_opt(i) = simIn_opt(i).setVariable('delta_theta_deg', scenarios(i, 2));
    simIn_opt(i) = simIn_opt(i).setVariable('P_fault',         scenarios(i, 3));
    simIn_opt(i) = simIn_opt(i).setVariable('Q_fault',         scenarios(i, 4));
    simIn_opt(i) = simIn_opt(i).setVariable('enable_breaker',  scenarios(i, 5));
end
out_opt = sim(simIn_opt); 

% --- Initialisation de toutes les variables ---
total_mse = 0; total_mae = 0;
total_mse_P = 0; total_mse_Q = 0;
total_mae_P = 0; total_mae_Q = 0;

for i = 1:num_runs
    try 
        if isprop(out_opt(i), 'ErrorMessage') && ~isempty(out_opt(i).ErrorMessage)
            error('Plantage Simulink intercepté.');
        end
        P_true = data_input(i).P_PCC.Data;
        Q_true = data_input(i).Q_PCC.Data; 
        t_true = data_input(i).P_PCC.Time;
        
        P_cand = out_opt(i).logsout.get('P_pcc').Values.Data;
        Q_cand = out_opt(i).logsout.get('Q_pcc').Values.Data;
        
        idx_start = find(t_true >= t_eval_start, 1, 'first');
        if isempty(idx_start), idx_start = 1; end
        
        len = min([length(P_true), length(P_cand), length(Q_true), length(Q_cand)]);
        
        if len >= idx_start
            P_t = P_true(idx_start:downsample_step:len); P_c = P_cand(idx_start:downsample_step:len);
            Q_t = Q_true(idx_start:downsample_step:len); Q_c = Q_cand(idx_start:downsample_step:len);
            
            err_P = P_t - P_c; err_Q = Q_t - Q_c;
            mse_P = mean(err_P.^2); mse_Q = mean(err_Q.^2);
            mae_P = mean(abs(err_P)); mae_Q = mean(abs(err_Q));
            
            total_mse_P = total_mse_P + mse_P; total_mse_Q = total_mse_Q + mse_Q;
            total_mae_P = total_mae_P + mae_P; total_mae_Q = total_mae_Q + mae_Q;
            total_mse = total_mse + mse_P + mse_Q;
            total_mae = total_mae + mae_P + mae_Q;
        end
    catch ME
        warning('Scénario %d a planté lors de l''évaluation finale.', i);
    end
end

% =========================================================================
% 8. Displaying and saving results
% =========================================================================
disp('=========================================');
disp('--- RÉSULTATS D''IDENTIFICATION ---');
for v = 1:num_vars
    fprintf('%-15s optimal: %7.4f\n', opt_var_names{v}, x_opt(v));
end
disp('-----------------------------------------');
fprintf('Fitness obj. final: %.4e\n', fval);
disp('-----------------------------------------');
fprintf('Total MSE (P+Q)   : %.4e\n', total_mse);
fprintf('  -> MSE (P)      : %.4e\n', total_mse_P);
fprintf('  -> MSE (Q)      : %.4e\n', total_mse_Q);
disp('=========================================');

% --- Sauvegarde du fichier .mat avec suffixe ---
if contains(func2str(ObjectiveFunction), 'MAE')
    resFileName = fullfile(outputFolder, sprintf('Results_GA+Hyb_%s_on_%s_ds%d%s_MAE.mat', modelName, targetDataName, downsample_step, run_suffix));
else
    resFileName = fullfile(outputFolder, sprintf('Results_GA+Hyb_%s_on_%s_ds%d%s_MSE.mat', modelName, targetDataName, downsample_step, run_suffix));
end

save(resFileName, 'x_opt', 'fval', 'total_mse', 'total_mae', ...
    'total_mse_P', 'total_mse_Q', 'total_mae_P', 'total_mae_Q', ...
    'modelName', 'bestModelName', 'targetDataName', 'downsample_step', 'opt_var_names');
disp([' -> Results successfully saved in ', resFileName]);

% ========================================================================
% FONCTION LOCALE : Wrapper de Fitness (4D Grid Mapping)
% ========================================================================
function score = fitness_sweep_wrapper(x, data_input, scenarios, opt_var_names, downsample_step, t_eval_start, sweepDir, baseModelName)
    
    % Extraction dynamique des valeurs
    idx_Ppv  = find(strcmp(opt_var_names, 'Ppv'));
    idx_Pcc  = find(strcmp(opt_var_names, 'Pcc'));
    idx_Perm = find(strcmp(opt_var_names, 'P_ERM'));
    idx_Qerm = find(strcmp(opt_var_names, 'Q_ERM'));
    
    % Grilles du sweep
    grid_Ppv  = 0.25 : 0.25 : 0.75; 
    grid_Pcc  = 0.25 : 0.25 : 0.75;
    grid_Perm = 5000 : 4000 : 13000;
    grid_Qerm = 100  : 700  : 1500;
    
    % Recherche de la valeur la plus proche
    [~, i1] = min(abs(grid_Ppv - x(idx_Ppv)));   Ppv_disc  = grid_Ppv(i1);
    [~, i2] = min(abs(grid_Pcc - x(idx_Pcc)));   Pcc_disc  = grid_Pcc(i2);
    [~, i3] = min(abs(grid_Perm - x(idx_Perm))); Perm_disc = grid_Perm(i3);
    [~, i4] = min(abs(grid_Qerm - x(idx_Qerm))); Qerm_disc = grid_Qerm(i4);
    
    strPpv  = strrep(sprintf('%.2f', Ppv_disc), '.', 'p');
    strPcc  = strrep(sprintf('%.2f', Pcc_disc), '.', 'p');
    strPerm = sprintf('%g', Perm_disc);
    strQerm = sprintf('%g', Qerm_disc);
    
    % Construction du nom exact du modèle
    modelSweepName = sprintf('%s_Ppv%s_Pcc%s_Pe%s_Qe%s', baseModelName, strPpv, strPcc, strPerm, strQerm);
    
    if ~bdIsLoaded(modelSweepName)
        load_system(modelSweepName);
    end
    
    score = fitness_MSE_PCC_NOpu(x, data_input, scenarios, modelSweepName, opt_var_names, downsample_step, t_eval_start);
end