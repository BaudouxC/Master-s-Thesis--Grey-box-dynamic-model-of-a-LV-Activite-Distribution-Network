% =========================================================================
% STEP 1: Ground Truth Generation - PQ
% =========================================================================
% 1. Define Simulink model name
modelName = 'PQ_GFL';
load_system(modelName);

% Create destination folder
outputFolder = fullfile(pwd, modelName); 
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
    disp(['Folder created: ', outputFolder]);
end

% 2. Define fixed configuration (Ground Truth)
wi_true    = 1500;
wff_true   = 2000;
wPLL_true  = 600;
Delay_true = 120e-6;
wp_true    = 15;

% Grouping parameters for future saving
true_parameters = struct();
true_parameters.wipq    = wi_true;
true_parameters.wffpq   = wff_true;
true_parameters.wpllpq  = wPLL_true;
true_parameters.Delaypq = Delay_true;
true_parameters.wppq    = wp_true;

% 3. Define Scenarios Matrix
% Columns: [delta_E, delta_theta_deg, P_load, Q_load, enable_breaker]
scenarios = [
    -0.1,    0,    5,   0,  0;  % Run 1: E step
    -0.05,  10,    5,   0,  0;  % Run 2: E + theta step
    +0.05,   5,    5,   0,  0;  % Run 3: E + theta step
    -0.0,    0, 1000,   0,  1;  % Run 4: Active load step
    -0.0,    0,  400, 200,  1;  % Run 5: Complex load step
    -0.0,    0,  600, 400,  1;  % Run 6: Complex load step
];
num_runs = size(scenarios, 1);

% 4. Prepare simulations
for i = num_runs:-1:1
    simIn(i) = Simulink.SimulationInput(modelName);
    
    simIn(i) = simIn(i).setVariable('wipq', wi_true);       
    simIn(i) = simIn(i).setVariable('wffpq', wff_true);     
    simIn(i) = simIn(i).setVariable('wpllpq', wPLL_true);
    simIn(i) = simIn(i).setVariable('Delaypq', Delay_true);
    simIn(i) = simIn(i).setVariable('wppq', wp_true);
    
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
GT_PQ = struct();
for i = 1:num_runs
    GT_PQ(i).P_PCC = out(i).logsout.get('<P>').Values;
    GT_PQ(i).Q_PCC = out(i).logsout.get('<Q>').Values;
    GT_PQ(i).V_PCC = out(i).logsout.get('<rms_pu>').Values;
    GT_PQ(i).f_PCC = out(i).logsout.get('<f>').Values;
    GT_PQ(i).scenario_config = scenarios(i, :);
end

% Save the .mat file into the specific folder
matFileName = fullfile(outputFolder, 'GT_PQ.mat');
save(matFileName, 'GT_PQ', 'scenarios', 'modelName', 'true_parameters');
disp(['GT_PQ and parameters saved in: ', matFileName]);

% =========================================================================
% STEP 1bis: Visualization and Saving of Curves
% =========================================================================
disp('Generating and saving figures in progress...');
varNames = {'P_PCC', 'Q_PCC', 'V_PCC', 'f_PCC'};
yLabels  = {'Active Power P', 'Reactive Power Q', 'Voltage V_{rms} (pu)', 'Frequency f (Hz)'};

scenario_titles = {
    '\Delta E = -0.1 pu', ...
    '\Delta E = -0.05 pu, \Delta \theta = 10^\circ', ...
    '\Delta E = +0.05 pu, \Delta \theta = 5^\circ', ...
    'Load: \Delta P = 1000', ...
    'Load: \Delta P = 400, \Delta Q = 200', ...
    'Load: \Delta P = 600, \Delta Q = 400'
};

modelName_disp = strrep(modelName, '_', '\_');

for v = 1:length(varNames)
    var = varNames{v};
    
    fig = figure('Name', sprintf('%s_%s', modelName, var), ...
                 'Position', [100, 100, 1400, 800], ...
                 'Visible', 'on'); 
             
    for i = 1:num_runs
        subplot(2, 3, i);
        t = GT_PQ(i).(var).Time;
        y = GT_PQ(i).(var).Data;
        
        plot(t, y, 'LineWidth', 1.5, 'Color', [0 0.4470 0.7410]); 
        grid on;
        title(scenario_titles{i}, 'FontSize', 11);
        xlabel('Time (s)', 'FontSize', 9);
        ylabel(yLabels{v}, 'FontSize', 9);
        xlim([min(t) max(t)]); 
    end
    
    sgtitle(sprintf('Model: %s | Observed Variable: %s', modelName_disp, yLabels{v}), 'FontSize', 16, 'FontWeight', 'bold');
    
    fileName_base = sprintf('%s_%s', modelName, var);
    fullPath_base = fullfile(outputFolder, fileName_base);
    
    savefig(fig, [fullPath_base, '.fig']);
    saveas(fig, [fullPath_base, '.png']);
    
    disp(['  -> ', fileName_base, ' (.fig & .png) saved in ', modelName]);
end
disp('All figures have been successfully generated and saved!');