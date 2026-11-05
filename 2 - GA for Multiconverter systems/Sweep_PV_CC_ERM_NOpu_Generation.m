%% =========================================================
%  SWEEP DES CONDITIONS INITIALES — PV_CC_ERM_NOpu
%  Pour chaque combinaison (Ppv, Pcc, P_ERM, Q_ERM) :
%    1. Copie du modèle de base sans p.u. avec un nom unique
%    2. Mise à jour des variables dans le workspace pour le LoadFlow
%    3. Exécution du Loadflow
%    4. Restauration des liens dynamiques dans les blocs (VSC + Charge)
%    5. Sauvegarde du modèle avec l'état initialisé
% =========================================================
clear; clc;

%% --- Chargement des variables d'initialisation ----------------
fprintf('=== Chargement des variables de configuration (init_PV_CC_ERM.m) ===\n');
if exist('init_PV_CC_ERM.m', 'file')
    evalin('base', 'init_PV_CC_ERM;'); 
    disp('✔ Variables du fichier init_PV_CC_ERM.m chargées avec succès.');
else
    warning('Le fichier init_PV_CC_ERM.m n''a pas été trouvé.');
end

%% --- Modèle de base -------------------------------------------
baseModel = 'PV_CC_ERM_NOpu'; % <-- Votre nouveau modèle sans p.u.
load_system(baseModel);

%% --- Grilles de balayage (Sécurisées avec le suffixe _vec) ----
Ppv_vec   = 0.25 : 0.25 : 0.75; 
Pcc_vec   = 0.25 : 0.25 : 0.75;
P_ERM_vec = 5e3 : 4e3 : 13e3;  % [5000, 9000, 13000] W
Q_ERM_vec = 100 : 700 : 1500;  % [100, 800, 1500] var

%% --- Répertoire de sortie -------------------------------------
outDir = pwd; % Sauvegarde dans le dossier courant (là où le GA ira les chercher)
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% --- Journal des combinaisons ---------------------------------
logFile = fullfile(outDir, 'sweep_PV_CC_ERM_NOpu_log.csv');
fid = fopen(logFile, 'w');
fprintf(fid, 'Model_name,Ppv_pu,Pcc_pu,P_ERM_W,Q_ERM_var,V_pu,angle_deg,status\n');

%% --- Compteur global ------------------------------------------
nTotal = length(Ppv_vec) * length(Pcc_vec) * length(P_ERM_vec) * length(Q_ERM_vec);
nDone  = 0;
fprintf('\n=== Démarrage du sweep %s : %d combinaisons ===\n\n', baseModel, nTotal);

%% --- Boucle principale ----------------------------------------
for iPv = 1:numel(Ppv_vec)
for iCc = 1:numel(Pcc_vec)
for iPE = 1:numel(P_ERM_vec)   
for iQE = 1:numel(Q_ERM_vec)   
    
    % -- Valeurs courantes du point de fonctionnement --
    Ppv_val  = Ppv_vec(iPv);
    Pcc_val  = Pcc_vec(iCc);
    Perm_val = P_ERM_vec(iPE); 
    Qerm_val = Q_ERM_vec(iQE); 
    
    nDone = nDone + 1;
    fprintf('[%d/%d] Ppv = %.2f pu | Pcc = %.2f pu | P_ERM = %g W | Q_ERM = %g var\n', ...
            nDone, nTotal, Ppv_val, Pcc_val, Perm_val, Qerm_val);
    
    % -- Nom unique du nouveau modèle --
    strPpv  = strrep(sprintf('%.2f', Ppv_val), '.', 'p');
    strPcc  = strrep(sprintf('%.2f', Pcc_val), '.', 'p');
    strPerm = sprintf('%g', Perm_val); 
    strQerm = sprintf('%g', Qerm_val);
    
    newName = sprintf('%s_Ppv%s_Pcc%s_Pe%s_Qe%s', baseModel, strPpv, strPcc, strPerm, strQerm);
    newPath = fullfile(outDir, [newName, '.slx']);
    
    % Initialisation des variables de log
    V_amplitude_pu = NaN;
    V_phase_deg    = NaN;
    status         = 'OK';
    
    try
        %% 1) Copie du modèle de base -------------------------
        if bdIsLoaded(newName), close_system(newName, 0); end
        copyfile([baseModel, '.slx'], newPath);
        load_system(newPath);
        
        %% 2) Injecter les valeurs numériques pour le LoadFlow --
        assignin('base', 'Ppv', Ppv_val);
        assignin('base', 'Pcc', Pcc_val);
        assignin('base', 'P_ERM', Perm_val);
        assignin('base', 'Q_ERM', Qerm_val);
        
        %% 3) Exécution du Load Flow --------------------------
        LoadFlow_VSC; 
        
        % Récupération des résultats du Load Flow Bus
        hLFBus = find_system(newName, ...
                             'LookUnderMasks', 'all', ...
                             'MaskType',       'Load Flow Bus');
                         
        if isempty(hLFBus)
            error('Aucun bloc "Load Flow Bus" trouvé.');
        end
        
        V_amplitude_pu = str2double(get_param(hLFBus{1}, 'VLF'));
        V_phase_deg    = str2double(get_param(hLFBus{1}, 'angleLF'));
        fprintf('   PCC_BUS → V = %.4f pu | θ = %.4f deg\n', V_amplitude_pu, V_phase_deg);
        
        %% 4) LIEN DYNAMIQUE : Réécriture des variables APRÈS le Load Flow
        
        % 4.a) Configuration du bloc PV (GFL IDEAL VSC)
        blocPV = [newName, '/GFL IDEAL VSC'];
        set_param(blocPV, 'P0', 'Ppv'); 
        fprintf('   ✔ Bloc PV restauré (Ppv)\n');
        
        % 4.b) Configuration du bloc CC (GFM_CC IDEAL_VSC1)
        blocCC = [newName, '/GFM_CC IDEAL_VSC1']; 
        set_param(blocCC, 'P0', 'Pcc'); 
        fprintf('   ✔ Bloc CC restauré (Pcc)\n');
        
        % 4.c) Restauration de la charge dynamique (ERM)
        blocERM = [newName, '/Three-Phase Dynamic Load']; 
        PoQo_str = '[P_ERM Q_ERM]';
        set_param(blocERM, 'ActiveReactivePowers', PoQo_str);
        fprintf('   ✔ Bloc ERM restauré dynamiquement : %s\n', PoQo_str);
        
        %% 5) Sauvegarde du modèle initialisé -----------------
        save_system(newName, newPath);
        close_system(newName, 0);
        fprintf('   ✔ Modèle sauvegardé avec succès : %s\n\n', newPath);
        
    catch ME
        status = ME.message;
        % --- LIGNE MAGIQUE POUR IDENTIFIER L'ERREUR ---
        fprintf(2, '🚨 ERREUR CRITIQUE SUR [%s] :\n -> Message : %s\n', newName, ME.message);
        if ~isempty(ME.stack)
            fprintf(2, ' -> Fichier : %s (Ligne %d)\n', ME.stack(1).name, ME.stack(1).line);
        end
        
        if bdIsLoaded(newName), close_system(newName, 0); end
    end
    
    % -- Journalisation CSV --
    fprintf(fid, '%s,%.2f,%.2f,%.0f,%.0f,%.4f,%.4f,%s\n', ...
            newName, Ppv_val, Pcc_val, Perm_val, Qerm_val, V_amplitude_pu, V_phase_deg, status);

end % iQE
end % iPE
end % iCc
end % iPv

%% --- Clôture --------------------------------------------------
fclose(fid);
fprintf('=== Sweep terminé (%d combinaisons). Journal : %s ===\n', nTotal, logFile);