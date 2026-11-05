% =========================================================================
% STEP 1: Ground Truth Generation - PV & CC Combined Model
% =========================================================================
% 1. Define Simulink model name
modelName = 'PV_CC'; 
load_system(modelName);

% Create destination folder
outputFolder = fullfile(pwd, modelName); 
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
    disp(['Folder created: ', outputFolder]);
end

% 2. Define fixed configuration (Ground Truth)
% --- PV Parameters ---
wi_pv_true    = 1500;
wff_pv_true   = 2000;
wPLL_pv_true  = 600;
Delay_pv_true = 120e-6;
wp_pv_true    = 15;
wv_pv_true    = 8;
Ppv_true      = 0.5; % Puissance active nominale fixe PV (pu)

% --- CC Parameters ---
H_cc_true      = 1.8;
ksi_cc_true    = 1.5;
wi_cc_true     = 1800;
wff_cc_true    = 2300;
Delay_cc_true  = 120e-6;
wQSEMv_cc_true = 75;
Pcc_true       = 0.5; % Puissance active nominale fixe CC (pu)

% Grouping parameters for future saving
true_parameters = struct();
% PV
true_parameters.wipv    = wi_pv_true;
true_parameters.wffpv   = wff_pv_true;
true_parameters.wpllpv  = wPLL_pv_true;
true_parameters.Delaypv = Delay_pv_true;
true_parameters.wppv    = wp_pv_true;
true_parameters.wvpv    = wv_pv_true;
true_parameters.Ppv     = Ppv_true;
% CC
true_parameters.Hcc      = H_cc_true;
true_parameters.ksicc    = ksi_cc_true;
true_parameters.wicc     = wi_cc_true;
true_parameters.wffcc    = wff_cc_true;
true_parameters.Delaycc  = Delay_cc_true;
true_parameters.wQSEMvcc = wQSEMv_cc_true;
true_parameters.Pcc      = Pcc_true;

% 3. Define Scenarios Matrix
% Each row is a simulation.
% Columns: [delta_E, delta_theta_deg, P_load, Q_load, enable_breaker]
scenarios = [
    -0.1,    0,  100,   0,  0;  % Run 1: E step
    -0.05,  10,  100,   0,  0;  % Run 2: E + theta step
    +0.05,   5,  100,   0,  0;  % Run 3: E + theta step
    -0.0,    0, 1000,   0,  1;  % Run 4: Active load step
    -0.0,    0,  400, 200,  1;  % Run 5: Complex load step
    -0.0,    0,  600, 400,  1;  % Run 6: Complex load step
];
num_runs = size(scenarios, 1);

% 4. Prepare simulations
for i = num_runs:-1:1
    simIn(i) = Simulink.SimulationInput(modelName);
    
    % Fix the PV parameters (Ground truth)
    simIn(i) = simIn(i).setVariable('wipv', wi_pv_true);       
    simIn(i) = simIn(i).setVariable('wffpv', wff_pv_true);     
    simIn(i) = simIn(i).setVariable('wpllpv', wPLL_pv_true);
    simIn(i) = simIn(i).setVariable('Delaypv', Delay_pv_true);
    simIn(i) = simIn(i).setVariable('wppv', wp_pv_true);
    simIn(i) = simIn(i).setVariable('wvpv', wv_pv_true); 
    simIn(i) = simIn(i).setVariable('Ppv', Ppv_true); 
    
    % Fix the CC parameters (Ground truth)
    simIn(i) = simIn(i).setVariable('Hcc', H_cc_true);       
    simIn(i) = simIn(i).setVariable('ksicc', ksi_cc_true);     
    simIn(i) = simIn(i).setVariable('wicc', wi_cc_true);
    simIn(i) = simIn(i).setVariable('wffcc', wff_cc_true);
    simIn(i) = simIn(i).setVariable('Delaycc', Delay_cc_true);
    simIn(i) = simIn(i).setVariable('wQSEMvcc', wQSEMv_cc_true);
    simIn(i) = simIn(i).setVariable('Pcc', Pcc_true); 
    
    % Fix the perturbation (Activate the right scenario, deactivate others)
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
matFileName = fullfile(outputFolder, 'GT_Combined.mat');
save(matFileName, 'GT_Combined', 'scenarios', 'modelName', 'true_parameters');
disp(['GT_Combined and parameters saved in: ', matFileName]);

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
    'Load: \Delta P = 400, \Delta Q = 200', ...
    'Load: \Delta P = 600, \Delta Q = 400'
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