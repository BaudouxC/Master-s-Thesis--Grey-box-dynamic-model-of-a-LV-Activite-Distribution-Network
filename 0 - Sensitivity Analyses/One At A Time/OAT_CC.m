%% 1. Analysis Configuration
modelName = 'CC_GFM';
load_system(modelName);


% Parameters to vary
paramNames = {'Hcc', 'ksicc', 'wicc', 'wffcc', 'Delaycc', 'wQSEMvcc'};
numParams = length(paramNames);

% Bounds [Min, Max]
lb = [0.7, 0.7, 1000, 1000, 50e-6, 36];
ub = [5, 3, 3000, 3000, 200e-6, 90];

% Valeurs du cas de base (Moyenne de l'intervalle)
base_vals = (lb + ub) / 2;

% Perturbation scenarios (4 scenarios)
scenarios = [
    1000,   0, 0.0, 0, 1; % Scenario 1: Active power fault
       0, 200, 0.0, 0, 1; % Scenario 2: Reactive power fault
       5,   0, -0.1, 0, 0; % Scenario 3: Voltage step
       5,   0, 0.0, 5, 0  % Scenario 4: Phase jump
];
numScenarios = size(scenarios, 1);

%% 2. Simulation Batch Preparation (OAT - One At A Time)
disp('Preparing Simulink objects for OAT Analysis...');
totalRuns = numScenarios * numParams * 3; % 3 runs (Base, Min, Max) per parameter per scenario
simIn(1:totalRuns) = Simulink.SimulationInput(modelName);

runIdx = 1;
for s = 1:numScenarios
    for p = 1:numParams
        for caseType = 1:3 % 1: Base, 2: Min, 3: Max
            
            % 1. Injecter d'abord TOUTES les valeurs à leur moyenne
            for j = 1:numParams
                simIn(runIdx) = simIn(runIdx).setVariable(paramNames{j}, base_vals(j));
            end
            
            % 2. Écraser spécifiquement le paramètre 'p' pour les cas extrêmes
            if caseType == 2
                simIn(runIdx) = simIn(runIdx).setVariable(paramNames{p}, lb(p)); % Cas Minimum
            elseif caseType == 3
                simIn(runIdx) = simIn(runIdx).setVariable(paramNames{p}, ub(p)); % Cas Maximum
            end
            
            % 3. Injecter le scénario réseau
            simIn(runIdx) = simIn(runIdx).setVariable('P_fault',         scenarios(s, 1));
            simIn(runIdx) = simIn(runIdx).setVariable('Q_fault',         scenarios(s, 2));
            simIn(runIdx) = simIn(runIdx).setVariable('delta_E',         scenarios(s, 3));
            simIn(runIdx) = simIn(runIdx).setVariable('delta_theta_deg', scenarios(s, 4));
            simIn(runIdx) = simIn(runIdx).setVariable('enable_breaker',  scenarios(s, 5));
            
            runIdx = runIdx + 1;
        end
    end
end

%% 3. Parallel Execution
disp('Initialisation du Workspace des workers...');
parfevalOnAll(gcp(), @evalin, 0, 'base', 'init');
disp('Workers prêts.');
disp(['Launching ', num2str(totalRuns), ' simulations with parsim...']);
out = parsim(simIn, 'ShowProgress', 'on');

%% 4. Extraction, Calculs de l'Erreur, Tracé et SAUVEGARDE
disp('Processing results, generating plots and saving...');

% --- Création d'un dossier pour ranger les images ---
outputFolder = 'Resultats_OAT_Images_CC_GFM';
if ~exist(outputFolder, 'dir')
    mkdir(outputFolder);
end

% Noms des signaux (Vérifie qu'ils correspondent bien à ton modèle)
signals = {'<P>', '<Q>', '<f>', '<rms_pu>'};
titles = {'Active Power (P)', 'Reactive Power (Q)', 'Frequency (f)', 'Voltage (V)'};

t_threshold = Tf; % Seuil pour l'analyse
runIdx = 1;

for s = 1:numScenarios
    for p = 1:numParams
        
        % Récupération des 3 résultats liés à ce paramètre
        out_base = out(runIdx);
        out_min  = out(runIdx + 1);
        out_max  = out(runIdx + 2);
        runIdx   = runIdx + 3;
        
        % Création de la figure (On capture le "handle" de la figure avec hFig)
        figName = sprintf('Scenario %d - Param: %s', s, paramNames{p});
        hFig = figure('Name', figName, 'Position', [100, 50, 1400, 800]);
        sgtitle(sprintf('Impact of %s (Scenario %d)', paramNames{p}, s), 'FontSize', 14, 'FontWeight', 'bold');
        
        for sigIdx = 1:4
            sigName = signals{sigIdx};
            
            % Vérification de sécurité : Les 3 runs ont-ils réussi ?
            if isempty(out_base.ErrorMessage) && isempty(out_min.ErrorMessage) && isempty(out_max.ErrorMessage)
                
                % Récupération des données
                t_vec  = out_base.logsout.get(sigName).Values.Time; 
                y_base = out_base.logsout.get(sigName).Values.Data;
                y_min  = out_min.logsout.get(sigName).Values.Data;
                y_max  = out_max.logsout.get(sigName).Values.Data;
                
                % Tracé
                subplot(2, 2, sigIdx);
                hold on;
                plot(t_vec, y_base, 'Color', [0.6 0.6 0.6], 'LineWidth', 2, 'DisplayName', 'Base (Mean)');
                plot(t_vec, y_min, 'Color', [0.3 0.7 1.0], 'LineWidth', 1.5, 'DisplayName', 'Min Bound');
                plot(t_vec, y_max, 'Color', [1.0 0.4 0.4], 'LineWidth', 1.5, 'DisplayName', 'Max Bound');
                
                % --- CALCUL DIRECT MAE et RMSE ---
                idx_valid = t_vec > t_threshold;
                
                if length(y_min) == length(y_max) && sum(idx_valid) > 0
                    y_min_valid = y_min(idx_valid);
                    y_max_valid = y_max(idx_valid);
                    
                    MAE  = mean(abs(y_max_valid - y_min_valid));
                    RMSE = sqrt(mean((y_max_valid - y_min_valid).^2));
                else
                    MAE = NaN; RMSE = NaN;
                end
                
                % Formatage
                title(sprintf('%s\nMAE: %.4g | RMSE: %.4g', titles{sigIdx}, MAE, RMSE));
                grid on;
                xlim([t_threshold-0.1, max(t_vec)]);
                
                if sigIdx == 1
                    legend('Location', 'best');
                end
                hold off;
            else
                % Si un des 3 runs a planté
                subplot(2, 2, sigIdx);
                title(sprintf('%s\nERREUR DE SIMULATION', titles{sigIdx}));
            end
        end
        
        % ========================================================
        % --- SAUVEGARDE DES FIGURES ---
        % Nom du fichier clair : ex: "PQ_GFL_Scen1_Param_wipq"
        baseFileName = sprintf('CC_GFM_Scen%d_Param_%s', s, paramNames{p});
        fullFilePath = fullfile(outputFolder, baseFileName);
        
        % 1. Sauvegarde en .fig (pour ré-éditer sous MATLAB plus tard)
        savefig(hFig, [fullFilePath '.fig']);
        
        % 2. Sauvegarde en .png (Haute qualité 300dpi)
        exportgraphics(hFig, [fullFilePath '.png'], 'Resolution', 300);
        
        % Décommenter la ligne ci-dessous pour éviter les ralentissements
        % d'affichage
        % close(hFig); 
        % ========================================================
        
    end
end
disp(['Analyse OAT terminée ! Les images sont sauvegardées dans le dossier : ', outputFolder]);