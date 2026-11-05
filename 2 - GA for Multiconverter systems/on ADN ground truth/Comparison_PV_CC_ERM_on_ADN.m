% =========================================================================
% STEP 3: Visual Validation - PV_CC_ERM_NOpu vs GT_ADN
% =========================================================================
clearvars;

% 1. Initialisation
disp('=== Chargement des variables (init_PV_CC_ERM.m) ===');
if exist('init_PV_CC_ERM.m', 'file')
    evalin('base', 'init_PV_CC_ERM;'); 
else
    warning('Le fichier init_PV_CC_ERM.m est introuvable.');
end

% 2. Configuration & Loading Data
targetDataName  = 'GT_ADN';          % <-- CIBLE COMPLEXE (ADN)
modelName       = 'PV_CC_ERM_NOpu';  % <-- MODÈLE SANS P.U.
downsample_step = 100;               % Doit correspondre au run GA
run_suffix      = '_on_ADN_Pop60_Gen100';  % <-- Suffixe du script GA précédent

% Ajouter le chemin des modèles du sweep
sweepDir = pwd; % Les modèles balayés doivent se trouver dans le dossier courant
addpath(sweepDir);

disp('Loading Ground Truth and Optimized Results...');

% --- Load Ground Truth (Recherche dans le dossier ADN) ---
if exist([targetDataName, '.mat'], 'file')
    temp_data = load([targetDataName, '.mat']);
else
    gtFolder = fullfile(pwd, 'ADN');
    if exist(fullfile(gtFolder, [targetDataName, '.mat']), 'file')
        temp_data = load(fullfile(gtFolder, [targetDataName, '.mat']));
    else
        error('Fichier Ground Truth introuvable : %s.mat', targetDataName);
    end
end

if isfield(temp_data, 'GT_Combined')
    gt_struct = temp_data.GT_Combined;
elseif isfield(temp_data, targetDataName)
    gt_struct = temp_data.(targetDataName);
else
    error('Structure Ground Truth introuvable dans le fichier .mat.');
end
scenarios = temp_data.scenarios;
num_runs  = size(scenarios, 1);

% --- Load GA+Hyb Results ---
outputFolder = fullfile(pwd, modelName);
% resFileName = fullfile(outputFolder, sprintf('Results_GA+Hyb_%s_on_%s_ds%d%s_MSE.mat', ...
%     modelName, targetDataName, downsample_step, run_suffix));
resFileName = sprintf('Results_GA+Hyb_%s_on_%s_ds%d%s_MSE.mat', ...
    modelName, targetDataName, downsample_step, run_suffix);

if ~exist(resFileName, 'file')
    error('Fichier de résultats introuvable : %s', resFileName);
end
load(resFileName); % Charge x_opt, fval, opt_var_names, etc.
num_vars = length(opt_var_names);

% =========================================================================
% 3. Model Selection (4D Sweep Logic)
% =========================================================================
% Recherche dynamique des index des variables pour plus de sécurité
idx_Ppv  = find(strcmp(opt_var_names, 'Ppv'));
idx_Pcc  = find(strcmp(opt_var_names, 'Pcc'));
idx_Perm = find(strcmp(opt_var_names, 'P_ERM'));
idx_Qerm = find(strcmp(opt_var_names, 'Q_ERM'));

% Grilles de balayage d'origine
grid_Ppv  = 0.25 : 0.25 : 0.75; 
grid_Pcc  = 0.25 : 0.25 : 0.75;
grid_Perm = 5000 : 4000 : 13000;
grid_Qerm = 100  : 700  : 1500;

% Trouver la valeur la plus proche sur chaque grille
[~, i1] = min(abs(grid_Ppv - x_opt(idx_Ppv)));   Ppv_disc  = grid_Ppv(i1);
[~, i2] = min(abs(grid_Pcc - x_opt(idx_Pcc)));   Pcc_disc  = grid_Pcc(i2);
[~, i3] = min(abs(grid_Perm - x_opt(idx_Perm))); Perm_disc = grid_Perm(i3);
[~, i4] = min(abs(grid_Qerm - x_opt(idx_Qerm))); Qerm_disc = grid_Qerm(i4);

strPpv  = strrep(sprintf('%.2f', Ppv_disc), '.', 'p');
strPcc  = strrep(sprintf('%.2f', Pcc_disc), '.', 'p');
strPerm = sprintf('%g', Perm_disc);
strQerm = sprintf('%g', Qerm_disc);

bestModelName = sprintf('%s_Ppv%s_Pcc%s_Pe%s_Qe%s', modelName, strPpv, strPcc, strPerm, strQerm);
disp(['Validation simulation using initialized model: ', bestModelName]);
load_system(bestModelName);

% =========================================================================
% 4. Simulating the model with the optimal parameters
% =========================================================================
for i = num_runs:-1:1
    simIn(i) = Simulink.SimulationInput(bestModelName);
    
    % Injection dynamique des paramètres optimisés
    for v = 1:num_vars
        simIn(i) = simIn(i).setVariable(opt_var_names{v}, x_opt(v), 'Workspace', bestModelName);
    end
    
    % Scénarios de perturbation
    simIn(i) = simIn(i).setVariable('delta_E',         scenarios(i, 1));
    simIn(i) = simIn(i).setVariable('delta_theta_deg', scenarios(i, 2));
    simIn(i) = simIn(i).setVariable('P_fault',         scenarios(i, 3));
    simIn(i) = simIn(i).setVariable('Q_fault',         scenarios(i, 4));
    simIn(i) = simIn(i).setVariable('enable_breaker',  scenarios(i, 5));
end
out_cand = sim(simIn);

% --- Vérification d'erreurs de simulation ---
for i = 1:num_runs
    if isprop(out_cand(i), 'ErrorMessage') && ~isempty(out_cand(i).ErrorMessage)
        error('Simulation Run %d failed:\n%s', i, out_cand(i).ErrorMessage);
    end
end
disp('Simulations completed. Generating plots...');

% =========================================================================
% 5. Construction dynamique du label et préparation des graphiques
% =========================================================================
opt_label_cand = '';
for v = 1:num_vars
    % %g pour un affichage propre des grandes valeurs de puissance (ex: 5000)
    opt_label_cand = [opt_label_cand, sprintf('%s=%.3g  ', opt_var_names{v}, x_opt(v))];
end
opt_label_cand = strtrim(opt_label_cand);

% Signaux à comparer : LES UNITÉS ONT ÉTÉ CHANGÉES DE (pu) À (W)/(V)/(var)
signals = {
    'P_pcc', 'P_PCC', 'Active Power P (W)',     'Active Power (P) Comparison';
    'Q_pcc', 'Q_PCC', 'Reactive Power Q (var)', 'Reactive Power (Q) Comparison';
    'V_pcc', 'V_PCC', 'Voltage V_{rms} (V)',    'Voltage at PCC (V) Comparison'
};
plot_ds = 1;
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

% Protection pour l'interpréteur TeX
bestModelName_disp  = strrep(bestModelName, '_', '\_');
targetDataName_disp = strrep(targetDataName, '_', '\_');

% =========================================================================
% 6. Génération des figures
% =========================================================================
for s = 1:size(signals, 1)
    sig_log = signals{s, 1};
    sig_gt  = signals{s, 2};
    sig_lab = signals{s, 3};
    sig_tit = signals{s, 4};
    
    if ~isfield(gt_struct, sig_gt)
        warning('Signal %s introuvable dans le Ground Truth. Ignoré.', sig_gt);
        continue; 
    end
    
    fig = figure('Name', sig_tit, 'Position', [50 + (s*50), 50, 1400, 700]);
    for i = 1:num_runs
        data_cand = out_cand(i).logsout.get(sig_log).Values.Data(1:plot_ds:end);
        t_cand    = out_cand(i).logsout.get(sig_log).Values.Time(1:plot_ds:end);
        
        data_true = gt_struct(i).(sig_gt).Data(1:plot_ds:end);
        t_true    = gt_struct(i).(sig_gt).Time(1:plot_ds:end);
        
        subplot(2, 3, i);
        plot(t_true, data_true, 'b',  'LineWidth', 2);   hold on;
        plot(t_cand, data_cand, 'r--','LineWidth', 1.5);
        xline(0.5, 'k:', 'Eval Start', 'LabelVerticalAlignment', 'bottom', 'HandleVisibility', 'off');
        title(sprintf('Run %d', i));
        ylabel(sig_lab);
        xlabel('Time (s)');
        grid on;
        xlim([min(t_true) max(t_true)]);
        
        if i == 1
            legend('ADN Ground Truth (Complex)', sprintf('Optimized [%s]', bestModelName_disp), 'Location', 'best');
        end
    end
    
    sgtitle(sprintf('%s\nModel: %s  |  Target: %s\nFitness (MSE): %.4e', ...
        sig_tit, bestModelName_disp, targetDataName_disp, fval), ...
        'FontSize', 13, 'FontWeight', 'bold');
        
    figName = fullfile(outputFolder, sprintf('Comparison_GA+Hyb_%s_on_%s_ds%d%s_%s', ...
        modelName, targetDataName, downsample_step, run_suffix, sig_gt));
    savefig(fig, [figName, '.fig']);
    saveas(fig,  [figName, '.png']);
    disp([' -> Plot saved: ', figName]);
end
disp('All comparison plots generated and saved successfully!');