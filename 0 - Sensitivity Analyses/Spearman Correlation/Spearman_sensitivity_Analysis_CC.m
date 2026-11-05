%% 1. Analysis Configuration
modelName = 'CC_GFM';
load_system(modelName);

% Parameters to vary (6 paramètres pour CC_GFM)
paramNames = {'Hcc', 'ksicc', 'wicc', 'wffcc', 'Delaycc', 'wQSEMvcc'};
numParams = length(paramNames);

% Bounds [Min, Max]
lb = [0.7, 0.7, 1000, 1000, 50e-6, 50];
ub = [5, 3, 3000, 3000, 200e-6, 83];

% Perturbation scenarios (4 scenarios)
% Columns: [P_fault, Q_fault, delta_E, delta_theta_deg, enable_breaker]
scenarios = [
    1000,   0, 0.0, 0, 1; % Scenario 1: Active power fault
       0, 500, 0.0, 0, 1; % Scenario 2: Reactive power fault
       5,   0, 0.1, 0, 0; % Scenario 3: Voltage step
       5,   0, 0.0, 5, 0  % Scenario 4: Phase jump
];
numScenarios = size(scenarios, 1);
numSamples = 200; % Number of samples per scenario (200 * 4 = 800 runs total)

%% 2. Global Design of Experiments (LHS)
disp('Generating LHS plan...');
normSamples = lhsdesign(numSamples, numParams); 
samples = zeros(numSamples, numParams);
for i = 1:numParams
    samples(:, i) = lb(i) + normSamples(:, i) * (ub(i) - lb(i));
end

%% 3. Simulation Batch Preparation (LHS x Scenarios)
disp('Preparing Simulink objects...');
totalRuns = numSamples * numScenarios;
simIn(1:totalRuns) = Simulink.SimulationInput(modelName);
runIdx = 1;
for s = 1:numScenarios
    for i = 1:numSamples
        % 1. Model parameter injection
        for p = 1:numParams
            simIn(runIdx) = simIn(runIdx).setVariable(paramNames{p}, samples(i, p));
        end
        
        % 2. Scenario parameter injection
        simIn(runIdx) = simIn(runIdx).setVariable('P_fault',         scenarios(s, 1));
        simIn(runIdx) = simIn(runIdx).setVariable('Q_fault',         scenarios(s, 2));
        simIn(runIdx) = simIn(runIdx).setVariable('delta_E',         scenarios(s, 3));
        simIn(runIdx) = simIn(runIdx).setVariable('delta_theta_deg', scenarios(s, 4));
        simIn(runIdx) = simIn(runIdx).setVariable('enable_breaker',  scenarios(s, 5));
        
        runIdx = runIdx + 1;
    end
end

%% 4. Parallel Execution
disp('Initialisation du Workspace des workers...');
parfevalOnAll(gcp(), @evalin, 0, 'base', 'init');
disp('Workers prêts.');
disp(['Launching ', num2str(totalRuns), ' simulations with parsim...']);

% FastRestart greatly speeds up execution if the structural model is unchanged
% Ajout de TransferBaseWorkspaceVariables pour la stabilité du calcul parallèle
out = parsim(simIn, 'ShowProgress', 'on', 'TransferBaseWorkspaceVariables', 'on');

%% 5. KPI Extraction (Key Performance Indicators) - ITAE
disp('Analyzing P, Q, V, and f curves (ITAE calculation)...');
kpi_P = zeros(totalRuns, 1);
kpi_Q = zeros(totalRuns, 1);
kpi_f = zeros(totalRuns, 1); 
kpi_V = zeros(totalRuns, 1); 

% Seuil de temps (ex: instant du défaut)
t_threshold = 0.2; 

for k = 1:totalRuns
    if isempty(out(k).ErrorMessage)
        % Récupération du vecteur temps 
        t_vec = out(k).logsout.get('<P>').Values.Time;
        idx_valid = t_vec > t_threshold;
        
        % Extraction des signaux
        P_cand = out(k).logsout.get('<P>').Values.Data(idx_valid);
        Q_cand = out(k).logsout.get('<Q>').Values.Data(idx_valid);
        f_cand = out(k).logsout.get('<f>').Values.Data(idx_valid); 
        V_cand = out(k).logsout.get('<rms_pu>').Values.Data(idx_valid);
        
        % Sécurité : vérifier qu'on a assez de points
        if ~isempty(P_cand) && length(P_cand) > 50
            % 1. Estimation du régime permanent (steady-state) sur les 50 derniers échantillons
            P_ss = mean(P_cand(end-50:end));
            Q_ss = mean(Q_cand(end-50:end));
            f_ss = mean(f_cand(end-50:end));
            V_ss = mean(V_cand(end-50:end));
            
            % 2. Calcul des erreurs absolues |e(t)|
            e_P = abs(P_cand - P_ss);
            e_Q = abs(Q_cand - Q_ss);
            e_f = abs(f_cand - f_ss);
            e_V = abs(V_cand - V_ss);
            
            % 3. Création du vecteur temps relatif (le chronomètre 't' de l'ITAE démarre à 0)
            t_rel = t_vec(idx_valid) - t_vec(find(idx_valid, 1));
            
            % 4. Calcul du KPI ITAE via intégration numérique (méthode des trapèzes)
            kpi_P(k) = trapz(t_rel, t_rel .* e_P);
            kpi_Q(k) = trapz(t_rel, t_rel .* e_Q);
            kpi_f(k) = trapz(t_rel, t_rel .* e_f);
            kpi_V(k) = trapz(t_rel, t_rel .* e_V);
            
        else
            warning('Run %d : Pas assez de données après t = %g s', k, t_threshold);
            kpi_P(k) = NaN; kpi_Q(k) = NaN; kpi_f(k) = NaN; kpi_V(k) = NaN;
        end
    else
        kpi_P(k) = NaN; kpi_Q(k) = NaN; kpi_f(k) = NaN; kpi_V(k) = NaN;
    end
end

%% 6. Sensitivity Calculation per Scenario and Plotting (Spearman)
disp('Generating sensitivity plots for P, Q, f, and V (Spearman)...');
% Matrices pour stocker les résultats
sens_P_matrix = zeros(numParams, numScenarios);
sens_Q_matrix = zeros(numParams, numScenarios);
sens_f_matrix = zeros(numParams, numScenarios);
sens_V_matrix = zeros(numParams, numScenarios);

for s = 1:numScenarios
    % Récupération des indices du scénario courant
    idx_start = (s - 1) * numSamples + 1;
    idx_end   = s * numSamples;
    
    kpi_P_scen = kpi_P(idx_start:idx_end);
    kpi_Q_scen = kpi_Q(idx_start:idx_end);
    kpi_f_scen = kpi_f(idx_start:idx_end);
    kpi_V_scen = kpi_V(idx_start:idx_end);
    
    % Nettoyage des NaN
    validIdx = ~isnan(kpi_P_scen) & ~isnan(kpi_Q_scen) & ~isnan(kpi_f_scen) & ~isnan(kpi_V_scen);
    
    % Vérification de sécurité
    if sum(validIdx) > 2
        % Calcul des corrélations de Spearman
        R_P = corr(samples(validIdx, :), kpi_P_scen(validIdx), 'Type', 'Spearman');
        R_Q = corr(samples(validIdx, :), kpi_Q_scen(validIdx), 'Type', 'Spearman');
        R_f = corr(samples(validIdx, :), kpi_f_scen(validIdx), 'Type', 'Spearman');
        R_V = corr(samples(validIdx, :), kpi_V_scen(validIdx), 'Type', 'Spearman');
        
        % Stockage des valeurs absolues
        sens_P_matrix(:, s) = abs(R_P);
        sens_Q_matrix(:, s) = abs(R_Q);
        sens_f_matrix(:, s) = abs(R_f);
        sens_V_matrix(:, s) = abs(R_V);
    else
        warning('Scénario %d : Trop d''échecs pour calculer la sensibilité.', s);
    end
end

% --- TRACÉ DES RÉSULTATS (GRILLE 2x2) ---
fig_bar = figure('Name', 'Multi-Criteria Sensitivity (Spearman) - CC_GFM', 'Position', [100, 50, 1400, 800]);

% 1. Sous-graphique pour P
subplot(2, 2, 1);
bar(sens_P_matrix);
set(gca, 'xticklabel', paramNames, 'TickLabelInterpreter', 'none');
ylabel('Impact on P (|r_{spearman}|)');
title('1. Sensitivity: Active Power Variation');
legend('Sc 1 (Active)', 'Sc 2 (Reactive)', 'Sc 3 (Voltage)', 'Sc 4 (Phase)', 'Location', 'best');
grid on;

% 2. Sous-graphique pour Q
subplot(2, 2, 2);
bar(sens_Q_matrix);
set(gca, 'xticklabel', paramNames, 'TickLabelInterpreter', 'none');
ylabel('Impact on Q (|r_{spearman}|)');
title('2. Sensitivity: Reactive Power Variation');
grid on;

% 3. Sous-graphique pour f
subplot(2, 2, 3);
bar(sens_f_matrix);
set(gca, 'xticklabel', paramNames, 'TickLabelInterpreter', 'none');
ylabel('Impact on f (|r_{spearman}|)');
title('3. Sensitivity: Frequency Variation');
grid on;

% 4. Sous-graphique pour V
subplot(2, 2, 4);
bar(sens_V_matrix);
set(gca, 'xticklabel', paramNames, 'TickLabelInterpreter', 'none');
ylabel('Impact on V (|r_{spearman}|)');
title('4. Sensitivity: Voltage Variation');
grid on;

% --- SAUVEGARDE DU GRAPHIQUE EN BARRES ---
disp('Saving Bar Plot...');
saveas(fig_bar, 'Sensitivity_BarPlot_CC_GFM.png');
savefig(fig_bar, 'Sensitivity_BarPlot_CC_GFM.fig');

%% 7. Scatter Plots (Analyse visuelle pour TOUS les scénarios)
disp('Generating Scatter Plots for all scenarios...');

for s = 1:numScenarios
    % Récupération des indices du scénario courant
    idx_start = (s - 1) * numSamples + 1;
    idx_end   = s * numSamples;
    
    % Extraction du KPI P pour ce scénario
    kpi_P_scen = kpi_P(idx_start:idx_end);
    
    % Nettoyage des NaN pour ce scénario spécifique
    validIdx = ~isnan(kpi_P_scen);
    
    % Création d'une nouvelle figure pour chaque scénario
    fig_scatter = figure('Name', sprintf('Scatter Plots: KPI P vs Parameters (Scenario %d) - CC_GFM', s), ...
           'Position', [150 + (s-1)*50, 100 + (s-1)*50, 1200, 600]);
    
    % Boucle sur les 6 paramètres (Grille 2x3 pour 6)
    for p = 1:numParams
        subplot(2, 3, p); 
        scatter(samples(validIdx, p), kpi_P_scen(validIdx), 20, 'filled', 'MarkerFaceAlpha', 0.6);
        
        xlabel(paramNames{p}, 'Interpreter', 'none');
        ylabel('KPI P (ITAE)'); 
        title(sprintf('Scen %d: P vs %s', s, paramNames{p}), 'Interpreter', 'none');
        grid on;
    end
    
    % --- SAUVEGARDE DE LA FIGURE DU SCÉNARIO COURANT ---
    disp(['Saving Scatter Plot for Scenario ', num2str(s), '...']);
    fileNamePNG = sprintf('ScatterPlot_CC_GFM_Scen%d.png', s);
    fileNameFIG = sprintf('ScatterPlot_CC_GFM_Scen%d.fig', s);
    
    saveas(fig_scatter, fileNamePNG);
    savefig(fig_scatter, fileNameFIG);
end

disp('Analysis Complete!');