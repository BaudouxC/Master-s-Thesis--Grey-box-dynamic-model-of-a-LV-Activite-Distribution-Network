% =========================================================================
% STEP 1: Ground Truth Generation - VC_GFM
% =========================================================================
% 1. Define Simulink model name
modelName = 'VC_GFM';
load_system(modelName);

% Create destination folder
outputFolder = fullfile(pwd, modelName); 
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
    disp(['Folder created: ', outputFolder]);
end

% 2. Define fixed configuration (Ground Truth)
H_true     = 1.8;
ksi_true   = 1.5;
Delay_true = 120e-6;
Rv_true    = 0.1;
W_TVR_true = 60;

% Grouping parameters for future saving
true_parameters = struct();
true_parameters.Hvc     = H_true;
true_parameters.ksivc   = ksi_true;
true_parameters.Delayvc = Delay_true;
true_parameters.Rvvc    = Rv_true;
true_parameters.W_TVRvc = W_TVR_true;

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
    
    % Fix the 5 converter parameters (Ground truth)
    simIn(i) = simIn(i).setVariable('Hvc', H_true);       
    simIn(i) = simIn(i).setVariable('ksivc', ksi_true);     
    simIn(i) = simIn(i).setVariable('Delayvc', Delay_true);
    simIn(i) = simIn(i).setVariable('Rvvc', Rv_true);
    simIn(i) = simIn(i).setVariable('W_TVRvc', W_TVR_true);
    
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
GT_VC = struct(); 
for i = 1:num_runs
    % Save the 4 variables
    GT_VC(i).P_PCC = out(i).logsout.get('<P>').Values;
    GT_VC(i).Q_PCC = out(i).logsout.get('<Q>').Values;
    GT_VC(i).V_PCC = out(i).logsout.get('<rms_pu>').Values;
    GT_VC(i).f_PCC = out(i).logsout.get('<f>').Values;
    GT_VC(i).scenario_config = scenarios(i, :); 
end

% Save the .mat file into the specific folder
matFileName = fullfile(outputFolder, 'GT_VC.mat');
save(matFileName, 'GT_VC', 'scenarios', 'modelName', 'true_parameters');
disp(['GT_VC and parameters saved in: ', matFileName]);

% =========================================================================
% STEP 1bis: Visualization and Saving of Curves
% =========================================================================
disp('Generating and saving figures in progress...');
% List of struct fields to plot, and their labels for Y axes
varNames = {'P_PCC', 'Q_PCC', 'V_PCC', 'f_PCC'};
yLabels  = {'Active Power P', 'Reactive Power Q', 'Voltage V_{rms} (pu)', 'Frequency f (Hz)'};

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
        t = GT_VC(i).(var).Time;
        y = GT_VC(i).(var).Data;
        
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