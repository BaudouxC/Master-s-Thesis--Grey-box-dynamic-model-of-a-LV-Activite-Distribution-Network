% =========================================================================
% STEP 2: GA + Hybrid FMINCON Optimization - Multi-Output
% =========================================================================
clearvars;
init;

% --- 1. SÉCURITÉ WORKSPACE PRINCIPAL (Client) ---
if exist('init.m', 'file')
    evalin('base', 'init;');
    disp('✔ Workspace principal initialisé (init.m).');
else
    warning('Le fichier init.m est introuvable.');
end

% --- AJOUT PATH : Dossiers nécessaires ---
wrapperDir = 'C:\Users\pcstudentgele11\Desktop\GeneticAlgorithm - Cyril Baudoux\6-GA_for_converter_association\Test_GA';
sweepDir = 'C:\Users\pcstudentgele11\Desktop\GeneticAlgorithm - Cyril Baudoux\6-GA_for_converter_association\Composition_Converter_Models';
if exist(wrapperDir, 'dir'), addpath(wrapperDir); else warning('Dossier wrapper introuvable.'); end
if exist(sweepDir, 'dir'),   addpath(sweepDir);   else warning('Dossier sweep introuvable.'); end

% --- 2. Configuration & Loading Ground Truth ---
targetDataName = 'GT_complex_composition';   
temp = load([targetDataName, '.mat']); 

if isfield(temp, targetDataName)
    data_input = temp.(targetDataName);
elseif isfield(temp, 'GT_Combined')
    data_input = temp.GT_Combined;  
else
    data_input = temp.data_input;
end
scenarios = temp.scenarios;
modelName = 'PV_CC';  

t_eval_start    = 0.5;    
downsample_step = 100; 

% ---> NOUVEAUTÉ : SUFFIXE POUR NE PAS ÉCRASER LES RÉSULTATS <---
run_suffix      = '_Pop50_Gen50_True'; % Changez ceci pour vos prochains tests (ex: '_Test3', '_Rapide')

% =========================================================================
% 3. GENERIC MAPPING CONFIGURATION (10 Variables for PV_CC)
% =========================================================================
opt_var_names = {'Ppv', 'wipv', 'wpllpv', 'wppv', 'wvpv', 'Pcc', 'Hcc', 'ksicc', 'wicc', 'wQSEMvcc'};
lb = [   0.1,   0.5,    0.5,    0.001,  0.002, 0.1,   0.001,  0.001,  0.5,    40 ];
ub = [   0.9,   4000,   4000,   200,    100,   0.9,   10,     10,     4000,   90 ]; 
num_vars = length(opt_var_names);

% =========================================================================
% 4. SÉCURITÉ WORKERS PARALLÈLES
% =========================================================================
disp('Préparation du pool parallèle pour GA et FMINCON...');
pool = gcp(); 
parfevalOnAll(pool, @addpath, 0, sweepDir); 
parfevalOnAll(pool, @addpath, 0, wrapperDir); 
f = parfevalOnAll(pool, @evalin, 0, 'base', 'init'); 
wait(f); 
disp('✔ Workers parallèles initialisés avec init.m !');

% =========================================================================
% 5. Configuration GA et FMINCON (Hybride)
% =========================================================================
% Astuce : Le wrapper de log gardera le même nom de base, mais écrasera le .csv en cours de route.
% Si vous voulez aussi un nom différent pour le log du wrapper, il faudrait le passer en argument.
outputFcnHandle = @(options, state, flag) log_GA_Evolution_wrapper( ...
    options, state, flag, modelName, targetDataName, downsample_step);

% Configuration de FMINCON
hybridOpts = optimoptions('fmincon', ...
    'MaxIterations', 100, ...
    'MaxFunctionEvaluations', 250, ...
    'UseParallel', true, ... 
    'Display', 'iter');

% Configuration du GA
options = optimoptions('ga', ...
    'PopulationSize',    50, ...          
    'MaxGenerations',    50, ...          
    'CrossoverFraction', 0.75, ...
    'MaxStallGenerations', 8, ...      
    'FunctionTolerance', 1e-8, ...     
    'Display',           'iter', ...             
    'PlotFcn',           @gaplotbestf, ...       
    'UseParallel',       true, ...
    'HybridFcn',         {@fmincon, hybridOpts}, ... 
    'OutputFcn',         outputFcnHandle);


ObjectiveFunction = @(x) fitness_sweep_wrapper( ...
    x, data_input, scenarios, opt_var_names, downsample_step, t_eval_start, sweepDir);

% =========================================================================
% 6. EXÉCUTION DE L'ALGORITHME
% =========================================================================
disp('=========================================================');
disp([' Démarrage de l''optimisation globale (GA -> FMINCON) : ', num2str(num_vars), ' variables']);
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
Ppv_disc = min(max(round(x_opt(1), 1), 0.1), 0.9);
Pcc_disc = min(max(round(x_opt(6), 1), 0.1), 0.9);
strPpv = strrep(sprintf('%.1f', Ppv_disc), '.', 'p');
strPcc = strrep(sprintf('%.1f', Pcc_disc), '.', 'p');
bestModelName = sprintf('PV_CC_Ppv%s_Pcc%s', strPpv, strPcc);
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
% FONCTION LOCALE : Wrapper de Fitness 
% ========================================================================
function score = fitness_sweep_wrapper(x, data_input, scenarios, opt_var_names, downsample_step, t_eval_start, sweepDir)
    Ppv_cand = x(1); Pcc_cand = x(6);
    Ppv_disc = min(max(round(Ppv_cand, 1), 0.1), 0.9); Pcc_disc = min(max(round(Pcc_cand, 1), 0.1), 0.9);
    strPpv = strrep(sprintf('%.1f', Ppv_disc), '.', 'p'); strPcc = strrep(sprintf('%.1f', Pcc_disc), '.', 'p');
    modelSweepName = sprintf('PV_CC_Ppv%s_Pcc%s', strPpv, strPcc);
    if ~bdIsLoaded(modelSweepName)
        load_system(modelSweepName);
    end
    score = fitness_MSE_PCC(x, data_input, scenarios, modelSweepName, opt_var_names, downsample_step, t_eval_start);
end