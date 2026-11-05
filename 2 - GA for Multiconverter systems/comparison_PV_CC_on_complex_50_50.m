% =========================================================================
% STEP 3: Visual Validation - PV_CC vs GT_complex_composition
% =========================================================================
clearvars;
init;

% 1. Configuration & Loading Data
targetDataName  = 'GT_complex_composition';  
modelName       = 'PV_CC';
downsample_step = 100;

% ---> AJOUT : Suffixe du run pour charger le bon fichier <---
run_suffix      = '_Pop50_Gen50_True'; 

% Ajouter le chemin des modèles du sweep pour la simulation
sweepDir = 'C:\Users\pcstudentgele11\Desktop\GeneticAlgorithm - Cyril Baudoux\6-GA_for_converter_association\Composition_Converter_Models';
addpath(sweepDir);

disp('Loading Ground Truth and Optimized Results...');

% --- Load Ground Truth ---
temp_data = load([targetDataName, '.mat']);
if isfield(temp_data, 'GT_Combined')
    gt_struct = temp_data.GT_Combined;
elseif isfield(temp_data, targetDataName)
    gt_struct = temp_data.(targetDataName);
else
    error('Structure Ground Truth introuvable dans le fichier .mat.');
end
scenarios = temp_data.scenarios;
num_runs  = size(scenarios, 1);

% --- Load GA+Hyb Results (avec le suffixe) ---
outputFolder = fullfile(pwd, modelName);
resFileName = fullfile(outputFolder, sprintf('Results_GA+Hyb_%s_on_%s_ds%d%s_MSE.mat', ...
    modelName, targetDataName, downsample_step, run_suffix));

if ~exist(resFileName, 'file')
    error('Fichier de résultats introuvable : %s', resFileName);
end
load(resFileName); % Charge x_opt, fval, opt_var_names, etc.
num_vars = length(opt_var_names);

% =========================================================================
% 2. Model Selection (Sweep Logic)
% =========================================================================
Ppv_disc = min(max(round(x_opt(1), 1), 0.1), 0.9);
Pcc_disc = min(max(round(x_opt(6), 1), 0.1), 0.9);
strPpv   = strrep(sprintf('%.1f', Ppv_disc), '.', 'p');
strPcc   = strrep(sprintf('%.1f', Pcc_disc), '.', 'p');
bestModelName = sprintf('%s_Ppv%s_Pcc%s', modelName, strPpv, strPcc);

disp(['Validation simulation using initialized model: ', bestModelName]);
load_system(bestModelName);

% =========================================================================
% 3. Simulating the model with the optimal parameters
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
% 4. Construction dynamique du label et préparation des graphiques
% =========================================================================
opt_label_cand = '';
for v = 1:num_vars
    opt_label_cand = [opt_label_cand, sprintf('%s=%.2f  ', opt_var_names{v}, x_opt(v))];
end
opt_label_cand = strtrim(opt_label_cand);

% Signaux à comparer
signals = {
    'P_pcc', 'P_PCC', 'Active Power P (pu)',   'Active Power (P) Comparison';
    'Q_pcc', 'Q_PCC', 'Reactive Power Q (pu)', 'Reactive Power (Q) Comparison';
    'V_pcc', 'V_PCC', 'Voltage V_{rms} (pu)',  'Voltage at PCC (V) Comparison'
};
plot_ds = 1;
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

% CORRECTION LATEX : Création des noms d'affichage protégés
bestModelName_disp  = strrep(bestModelName, '_', '\_');
targetDataName_disp = strrep(targetDataName, '_', '\_');

% =========================================================================
% 5. Génération des figures
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
            % Utilisation du nom protégé dans la légende
            legend('Ground Truth (Complex)', sprintf('Optimized [%s]', bestModelName_disp), 'Location', 'best');
        end
    end
    
    % Titre global de la figure avec noms protégés
    sgtitle(sprintf('%s\nModel: %s  |  Target: %s\nIdentified: %s  |  Fitness (MSE): %.4e', ...
        sig_tit, bestModelName_disp, targetDataName_disp, opt_label_cand, fval), ...
        'FontSize', 13, 'FontWeight', 'bold');
        
    % Sauvegarde des figures (inclusion du run_suffix dans le nom de fichier)
    figName = fullfile(outputFolder, sprintf('Comparison_GA+Hyb_%s_on_%s_ds%d%s_%s', ...
        modelName, targetDataName, downsample_step, run_suffix, sig_gt));
    savefig(fig, [figName, '.fig']);
    saveas(fig,  [figName, '.png']);
    disp([' -> Plot saved: ', figName]);
end
disp('All comparison plots generated and saved successfully!');