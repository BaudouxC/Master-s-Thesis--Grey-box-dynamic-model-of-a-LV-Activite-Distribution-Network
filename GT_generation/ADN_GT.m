% =========================================================================
% STEP 1: Ground Truth Generation - ADN Model
% =========================================================================
clearvars;

% 1. Initialisation du Workspace
disp('=== Chargement des variables de configuration (init_ADN.m) ===');
if exist('init_ADN.m', 'file')
    evalin('base', 'init_ADN;'); 
    disp('✔ Variables chargées avec succès.');
else
    warning('Le fichier init_ADN.m n''a pas été trouvé. Assurez-vous qu''il est dans le dossier.');
end

% 2. Define Simulink model name
modelName = 'ADN'; 
load_system(modelName);

% Create destination folder
outputFolder = fullfile(pwd, modelName); 
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
    disp(['Folder created: ', outputFolder]);
end

% 3. Define Scenarios Matrix
% Each row is a simulation.
% Columns: [delta_E, delta_theta_deg, P_fault, Q_fault, enable_breaker]
scenarios = [
    -0.1,    0,  100,   0,  0;  % Run 1: E step
    -0.05,  10,  100,   0,  0;  % Run 2: E + theta step
    +0.05,   5,  100,   0,  0;  % Run 3: E + theta step
    -0.0,    0, 2000,   0,  1;  % Run 4: Active load step
    -0.0,    0,  500, 10,  1;  % Run 5: Complex load step
    -0.0,    0,  800, 50,  1;  % Run 6: Complex load step
];
num_runs = size(scenarios, 1);

% 4. Prepare simulations
for i = num_runs:-1:1
    simIn(i) = Simulink.SimulationInput(modelName);
    
    % On n'injecte ici que les variables liées aux scénarios de perturbation.
    simIn(i) = simIn(i).setVariable('delta_E', scenarios(i, 1));
    simIn(i) = simIn(i).setVariable('delta_theta_deg', scenarios(i, 2));
    simIn(i) = simIn(i).setVariable('P_fault', scenarios(i, 3));
    simIn(i) = simIn(i).setVariable('Q_fault', scenarios(i, 4));
    simIn(i) = simIn(i).setVariable('enable_breaker', scenarios(i, 5));
end

% 5. Execute simulations in batch
disp(['Generating ground truth (', num2str(num_runs), ' scenarios) in progress...']);
out = sim(simIn); 

% 6. Extract and save data
GT_Combined = struct(); 
for i = 1:num_runs
    % Extraction des 3 variables de logsout (V, P, Q)
    GT_Combined(i).V_PCC = out(i).logsout.get('V_pcc').Values;
    GT_Combined(i).P_PCC = out(i).logsout.get('P_pcc').Values;
    GT_Combined(i).Q_PCC = out(i).logsout.get('Q_pcc').Values;
    
    GT_Combined(i).scenario_config = scenarios(i, :); 
end

% Save the .mat file into the specific folder
matFileName = fullfile(outputFolder, 'GT_ADN.mat');
save(matFileName, 'GT_Combined', 'scenarios', 'modelName');
disp(['GT_ADN saved in: ', matFileName]);


% =========================================================================
% STEP 1bis: Visualization and Saving of Curves
% =========================================================================
disp('Generating and saving figures in progress...');

% List of struct fields to plot, and their labels for Y axes
varNames = {'V_PCC', 'P_PCC', 'Q_PCC'};
yLabels  = {
    'Voltage V_{pcc} (pu)', ...
    'Active Power P_{pcc} (pu)', ...
    'Reactive Power Q_{pcc} (pu)'
};

% Define explicit titles for each subplot based on scenarios
scenario_titles = {
    '\Delta E = -0.1 pu', ...
    '\Delta E = -0.05 pu, \Delta \theta = 10^\circ', ...
    '\Delta E = +0.05 pu, \Delta \theta = 5^\circ', ...
    'Load: \Delta P = 1000', ...
    'Load: \Delta P = 400, \Delta Q = 100', ...
    'Load: \Delta P = 600, \Delta Q = 200'
};

% Create a version of the model name without TeX formatting for display
modelName_disp = strrep(modelName, '_', '\_');

for v = 1:length(varNames)
    var = varNames{v};
    
    % Create a new figure (size adjusted for 2x3 grid)
    fig = figure('Name', sprintf('%s_%s', modelName, var), ...
                 'Position', [100, 100, 1400, 800], ...
                 'Visible', 'on'); 
             
    for i = 1:num_runs
        subplot(2, 3, i);
        
        % Extract time and data from the timeseries
        t = GT_Combined(i).(var).Time;
        y = GT_Combined(i).(var).Data;
        
        % Plot
        plot(t, y, 'LineWidth', 1.5, 'Color', [0 0.4470 0.7410]); 
        grid on;
        
        % Graph aesthetics: Using dynamic titles
        title(scenario_titles{i}, 'FontSize', 11);
        xlabel('Time (s)', 'FontSize', 9);
        ylabel(yLabels{v}, 'FontSize', 9);
        
        % Automatic time zoom (to avoid empty margins at the beginning/end)
        xlim([min(t) max(t)]); 
    end
    
    % Global title of the figure identifying the Model and Variable
    sgtitle(sprintf('Model: %s | Observed Variable: %s', modelName_disp, yLabels{v}), 'FontSize', 16, 'FontWeight', 'bold');
    
    % Output file names and paths
    fileName_base = sprintf('%s_%s', modelName, var);
    fullPath_base = fullfile(outputFolder, fileName_base);
    
    % Saving files
    savefig(fig, [fullPath_base, '.fig']);
    saveas(fig, [fullPath_base, '.png']);
    
    disp(['  -> ', fileName_base, ' (.fig & .png) saved in ', modelName]);
end
disp('All figures have been successfully generated and saved!');