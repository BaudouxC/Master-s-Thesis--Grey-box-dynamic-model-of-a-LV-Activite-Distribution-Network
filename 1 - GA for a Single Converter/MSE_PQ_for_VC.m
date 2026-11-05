% =========================================================================
% STEP 2: GA Optimization - Multi-Output (P and Q in p.u. post-fault)
% =========================================================================

% 1. Configuration & Loading Ground Truth
targetDataName = 'GT_VC';   % The ground truth data you want to imitate
load([targetDataName, '.mat']); 
data_input = eval(targetDataName);

modelName = 'PQ_GFL';  % The model currently optimized /!\: modelName is a variable in the GT
load_system(modelName);

% Time & Downsampling configuration
t_eval_start    = 0.5;    


% =========================================================================
% 2. GENERIC MAPPING CONFIGURATION 
% Define ONLY the variables to optimize. The rest is handled by init.m
% =========================================================================
opt_var_names = {'wipq', 'wpllpq', 'wppq'};

% Search bounds
lb = [0.5, 0.5, 0.001]; 
ub = [4000, 4000, 20]; 
num_vars = length(opt_var_names); 

% =========================================================================
% 3. Advanced Genetic Algorithm Configuration
% =========================================================================

% FIX #1 — OutputFcn : utilisation d'un wrapper nommé pour capturer
%           correctement [state, options, optchanged] en retour.
%           L'anonymous function @(opts,state,flag)... ne retournait rien,
%           ce qui pouvait provoquer un comportement indéfini du GA.
outputFcnHandle = @(options, state, flag) log_GA_Evolution_wrapper( ...
    options, state, flag, modelName, targetDataName, downsample_step);

hybridOpts = optimoptions('fmincon', ...
    'MaxIterations',   50, ...
    'MaxFunctionEvaluations', 200, ...
    'Display', 'iter');

options = optimoptions('ga', ...
    'PopulationSize',    40, ...          
    'MaxGenerations',    40, ...          
    'CrossoverFraction', 0.75, ...
    'MaxStallGenerations', 5, ...      % EARLY STOPPING : S'arrête si pas d'amélioration pdt 5 générations
    'FunctionTolerance', 1e-6, ...     % Le seuil d'amélioration minimale (si le score baisse de moins de 1e-6, c'est ignoré)    
    'Display',           'iter', ...             
    'PlotFcn',           @gaplotbestf, ...       
    'UseParallel',       true, ...
    'HybridFcn',         {@fmincon, hybridOpts}, ...         
    'OutputFcn',         outputFcnHandle);

% 4. Cost function definition
ObjectiveFunction = @(x) fitness_MSE( ...
    x, data_input, scenarios, modelName, opt_var_names, downsample_step, t_eval_start);

% 5. Starting the optimization
disp('=========================================================');
disp([' Starting Genetic Algorithm on ', num2str(num_vars), ' variables']);
fprintf(' (Evaluation focused on transient state t >= %.2fs)\n', t_eval_start);
fprintf(' (Downsampling step: %d)\n', downsample_step);
disp([' Optimizing Model: [', modelName, '] to fit Data: [', targetDataName, ']']);
disp('=========================================================');

% --- PARALLEL SETUP (WITH WAIT) ---
pool = gcp(); 
parfevalOnAll(pool, @load_system, 0, modelName);
f = parfevalOnAll(pool, @evalin, 0, 'base', 'init'); 
wait(f); 
disp('Cores ready! Starting GA...');
% -----------------------------------

[x_opt, fval] = ga(ObjectiveFunction, num_vars, [], [], [], [], lb, ub, [], options);

% --- Ensure the target folder exists before saving anything ---
outputFolder = fullfile(pwd, modelName); 
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% --- Save the GA Convergence Plot ---
gaFig = gcf; 
figBaseName = fullfile(outputFolder, sprintf('Convergence_GA_%s_on_%s_ds%d_MSE', ...
    modelName, targetDataName, downsample_step));
savefig(gaFig, [figBaseName, '.fig']);
saveas(gaFig,  [figBaseName, '.png']);
disp([' -> Convergence plot successfully saved in ', outputFolder]);

% =========================================================================
% 6. Post-Optimization: Calculate RMSE and MAE
% =========================================================================
disp('Calculating final RMSE and MAE with optimal parameters...');
num_runs = size(scenarios, 1);

for i = num_runs:-1:1
    simIn_opt(i) = Simulink.SimulationInput(modelName);
    
    % FIX #2 — 'Workspace' explicitement spécifié, cohérent avec fitness_MSE.m
    for v = 1:num_vars
        simIn_opt(i) = simIn_opt(i).setVariable( ...
            opt_var_names{v}, x_opt(v), 'Workspace', modelName);
    end
    
    % Scenarios
    simIn_opt(i) = simIn_opt(i).setVariable('delta_E',         scenarios(i, 1));
    simIn_opt(i) = simIn_opt(i).setVariable('delta_theta_deg', scenarios(i, 2));
    simIn_opt(i) = simIn_opt(i).setVariable('P_fault',         scenarios(i, 3));
    simIn_opt(i) = simIn_opt(i).setVariable('Q_fault',         scenarios(i, 4));
    simIn_opt(i) = simIn_opt(i).setVariable('enable_breaker',  scenarios(i, 5));
end

out_opt = sim(simIn_opt); 
total_rmse = 0;
total_mae  = 0;

for i = 1:num_runs
    P_true = data_input(i).P_PCC.Data;
    Q_true = data_input(i).Q_PCC.Data; 
    t_true = data_input(i).P_PCC.Time;

    % FIX #3 — Vérification que Q_PCC est bien sur le même axe temporel que P_PCC
    t_true_Q = data_input(i).Q_PCC.Time;
    if ~isequal(t_true, t_true_Q)
        warning('Scenario %d : P_PCC.Time et Q_PCC.Time different — Q ignoré pour ce scénario.', i);
        continue;
    end
    
    P_cand = out_opt(i).logsout.get('<P>').Values.Data;
    Q_cand = out_opt(i).logsout.get('<Q>').Values.Data;
    
    idx_start = find(t_true >= t_eval_start, 1, 'first');
    if isempty(idx_start), idx_start = 1; end
    
    len = min([length(P_true), length(P_cand), length(Q_true), length(Q_cand)]);
    
    if len >= idx_start
        P_t = P_true(idx_start:downsample_step:len); 
        P_c = P_cand(idx_start:downsample_step:len);
        Q_t = Q_true(idx_start:downsample_step:len); 
        Q_c = Q_cand(idx_start:downsample_step:len);
        
        err_P = P_t - P_c;
        err_Q = Q_t - Q_c;
        
        rmse_P = sqrt(mean(err_P.^2));
        rmse_Q = sqrt(mean(err_Q.^2));
        total_rmse = total_rmse + rmse_P + rmse_Q;
        
        mae_P = mean(abs(err_P));
        mae_Q = mean(abs(err_Q));
        total_mae = total_mae + mae_P + mae_Q;
    end
end

% =========================================================================
% 7. Displaying and saving results
% =========================================================================
disp('=========================================');
disp('--- IDENTIFICATION RESULTS ---');
for v = 1:num_vars
    fprintf('%-15s optimal: %7.4f\n', opt_var_names{v}, x_opt(v));
end
disp('-----------------------------------------');
fprintf('Fitness (Sum MSE) : %.4e\n', fval);
fprintf('Total RMSE        : %.4e\n', total_rmse);
fprintf('Total MAE         : %.4e\n', total_mae);
disp('=========================================');

resFileName = fullfile(outputFolder, sprintf('Results_GA_%s_on_%s_ds%d_MSE.mat', ...
    modelName, targetDataName, downsample_step));
save(resFileName, 'x_opt', 'fval', 'total_rmse', 'total_mae', ...
    'modelName', 'targetDataName', 'downsample_step', 'opt_var_names');
disp([' -> Results successfully saved in ', resFileName]);