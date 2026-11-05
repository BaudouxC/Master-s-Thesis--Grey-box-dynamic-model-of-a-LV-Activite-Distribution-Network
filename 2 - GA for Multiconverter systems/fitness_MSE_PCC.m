% Fichier : fitness_MSE.m
function total_error = fitness_MSE_PCC(x, ground_truth, scenarios, modelName, opt_var_names, downsample_step, t_eval_start)
    wP = 1;
    wQ = 1;
    num_runs = size(scenarios, 1);
    num_vars = length(opt_var_names);

    % --- Affichage du vecteur candidat évalué ---
    fprintf('[FITNESS] x = ');
    fprintf('%.4f  ', x);
    fprintf('\n');
    % --------------------------------------------

    for i = num_runs:-1:1
        simIn(i) = Simulink.SimulationInput(modelName);

        % FIX CRITIQUE — 'Workspace', modelName est OBLIGATOIRE
        % Sans ça, setVariable n'injecte rien dans le modèle :
        % Simulink utilise les valeurs par défaut pour tous les candidats
        % => output identique => score constant => GA bloqué
        for v = 1:num_vars
            simIn(i) = simIn(i).setVariable(opt_var_names{v}, x(v), 'Workspace', modelName);
        end

        % Fault scenarios (pas de workspace ici : variables externes au modèle)
        simIn(i) = simIn(i).setVariable('delta_E',         scenarios(i, 1));
        simIn(i) = simIn(i).setVariable('delta_theta_deg', scenarios(i, 2));
        simIn(i) = simIn(i).setVariable('P_fault',         scenarios(i, 3));
        simIn(i) = simIn(i).setVariable('Q_fault',         scenarios(i, 4));
        simIn(i) = simIn(i).setVariable('enable_breaker',  scenarios(i, 5));
    end

    try
        out_cand = sim(simIn);
        total_error = 0;

        for i = 1:num_runs
            P_true = ground_truth(i).P_PCC.Data;
            Q_true = ground_truth(i).Q_PCC.Data;
            t_true = ground_truth(i).P_PCC.Time;

            if isempty(P_true)
                continue;
            end

            % FIX MINEUR — vérification cohérence axe temporel P et Q
            t_true_Q = ground_truth(i).Q_PCC.Time;
            if ~isequal(t_true, t_true_Q)
                warning('fitness_MSE: Scénario %d — P_PCC.Time ~= Q_PCC.Time, scénario ignoré.', i);
                total_error = total_error + 1e6;
                continue;
            end

            P_cand = out_cand(i).logsout.get('P_pcc').Values.Data;
            Q_cand = out_cand(i).logsout.get('Q_pcc').Values.Data;

            idx_start = find(t_true >= t_eval_start, 1, 'first');
            if isempty(idx_start), idx_start = 1; end

            len = min([length(P_true), length(P_cand), length(Q_true), length(Q_cand)]);

            if len >= idx_start
                P_t = P_true(idx_start:downsample_step:len);
                P_c = P_cand(idx_start:downsample_step:len);
                Q_t = Q_true(idx_start:downsample_step:len);
                Q_c = Q_cand(idx_start:downsample_step:len);
                eval_len = length(P_t);

                err_P = P_t - P_c;
                err_Q = Q_t - Q_c;

                mse_P = sum(err_P.^2) / eval_len;
                mse_Q = sum(err_Q.^2) / eval_len;

                total_error = total_error + (wP * mse_P + wQ * mse_Q);

                % Diagnostic léger par scénario (à commenter une fois validé)
                %fprintf('  [Scen %d] MSE_P=%.6f | MSE_Q=%.6f\n', i, mse_P, mse_Q);
            else
                total_error = total_error + 1e6;
            end
        end

        %fprintf('  => Score total = %.10f\n', total_error);

    catch ME
        fprintf('  [CATCH] %s\n', ME.message);
        total_error = 6e6;
    end
end