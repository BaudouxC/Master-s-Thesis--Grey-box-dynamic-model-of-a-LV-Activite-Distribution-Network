% =========================================================================
% STEP 3: Visual Validation - Integral Comparison (From t = 0s)
% =========================================================================

% 1. Configuration and Loading Data
targetDataName     = 'GT_VC';    % Ground truth à imiter
downsample_step_ga = downsample_step;

disp('Loading Ground Truth and GA Results...');

% Load Ground Truth
load([targetDataName, '.mat']);
modelName = 'PQ_GFL';  % Réassignation post-load (protection contre collision)

% Load GA Results (contient : x_opt, fval, opt_var_names, downsample_step, ...)
resFileName = fullfile(pwd, modelName, sprintf('Results_GA_%s_on_%s_ds%d_MSE.mat', ...
    modelName, targetDataName, downsample_step_ga));
load(resFileName);

load_system(modelName);

num_runs = size(scenarios, 1);
num_vars = length(opt_var_names);

% 2. Simulating the model with the optimal parameters
% Les paramètres NON optimisés sont déjà à leur valeur correcte via init.m
% => on n'injecte ici QUE les paramètres identifiés par le GA
disp('Validation simulation with optimal parameters in progress...');
for i = num_runs:-1:1
    simIn(i) = Simulink.SimulationInput(modelName);

    % Injection dynamique des paramètres optimisés uniquement
    for v = 1:num_vars
        simIn(i) = simIn(i).setVariable(opt_var_names{v}, x_opt(v), 'Workspace', modelName);
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
    if ~isempty(out_cand(i).ErrorMessage)
        error('Simulation Run %d failed:\n%s', i, out_cand(i).ErrorMessage);
    end
end

disp('Simulations completed. Generating plots...');

% 3. Construction dynamique du label des paramètres optimisés pour les titres
opt_label_cand = '';
opt_label_true = '';
for v = 1:num_vars
    opt_label_cand = [opt_label_cand, sprintf('%s=%.2f  ', opt_var_names{v}, x_opt(v))];
end
opt_label_cand = strtrim(opt_label_cand);

% 4. Signaux à comparer
% Format : {Signal_logsout, Champ_GT, Label_Y, Titre_figure}
signals = {
    '<P>',      'P_PCC', 'Active Power P (pu)',   'Active Power (P) Comparison';
    '<Q>',      'Q_PCC', 'Reactive Power Q (pu)', 'Reactive Power (Q) Comparison';
    '<rms_pu>', 'V_PCC', 'Voltage V_{rms} (pu)',  'Voltage at PCC (V) Comparison';
    '<f>',      'f_PCC', 'Frequency f (Hz)',      'Frequency (f) Comparison'
};

plot_ds      = 1;
outputFolder = fullfile(pwd, modelName);
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end

% 5. Génération des figures (une par type de signal)
for s = 1:size(signals, 1)
    sig_log = signals{s, 1};
    sig_gt  = signals{s, 2};
    sig_lab = signals{s, 3};
    sig_tit = signals{s, 4};

    % Vérifier que le signal existe dans le GT (robustesse si GT partiel)
    if ~isfield(scenarios, sig_gt) && ~isfield(eval(targetDataName), sig_gt)
        % tentative de lecture : si le champ n'existe pas, on saute
    end

    fig = figure('Name', sig_tit, 'Position', [50 + (s*50), 50, 1400, 700]);

    for i = 1:num_runs
        data_cand = out_cand(i).logsout.get(sig_log).Values.Data(1:plot_ds:end);
        t_cand    = out_cand(i).logsout.get(sig_log).Values.Time(1:plot_ds:end);

        gt_struct = eval(targetDataName);  % Accès dynamique à la struct GT (GT_VC ou GT_PQ)
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
            legend('Ground Truth', sprintf('Optimized [%s]', modelName), 'Location', 'best');
        end
    end

    % Titre global : paramètres optimisés identifiés + fitness
    sgtitle(sprintf('%s\nModel: %s  |  Target: %s\nIdentified: %s  |  Fitness: %.4e', ...
        sig_tit, modelName, targetDataName, opt_label_cand, fval), ...
        'FontSize', 13, 'FontWeight', 'bold');

    % Sauvegarde
    figName = fullfile(outputFolder, sprintf('Comparison_%s_on_%s_ds%d_%s_MSE', ...
        modelName, targetDataName, downsample_step_ga, sig_gt));
    savefig(fig, [figName, '.fig']);
    saveas(fig,  [figName, '.png']);
    disp([' -> Plot saved: ', figName]);
end

disp('All comparison plots generated and saved successfully!');