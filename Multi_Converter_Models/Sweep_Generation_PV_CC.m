%% =========================================================
%  SWEEP DES CONDITIONS INITIALES — PV_CC (Ppv & Pcc)
%  Pour chaque combinaison de puissance (Ppv, Pcc) :
%    1. Copie du modèle de base avec un nom unique
%    2. Mise à jour de Ppv et Pcc dans le workspace pour le LoadFlow
%    3. Exécution du Loadflow
%    4. Restauration des liens dynamiques 'Ppv' et 'Pcc' dans les blocs
%    5. Sauvegarde du modèle avec l'état initialisé
% =========================================================
clear; clc;

%% --- Chargement des variables d'initialisation ----------------
fprintf('=== Chargement des variables de configuration (init.m) ===\n');
if exist('init.m', 'file')
    evalin('base', 'init;'); 
    disp('✔ Variables du fichier init.m chargées avec succès.');
else
    warning('Le fichier init.m n''a pas été trouvé.');
end

%% --- Modèle de base -------------------------------------------
baseModel = 'PV_CC'; 
load_system(baseModel);

%% --- Grilles de balayage (de 0.1 à 0.9) -----------------------
Ppv_vec = 0.1 : 0.1 : 0.9; 
Pcc_vec = 0.1 : 0.1 : 0.9; 

%% --- Répertoire de sortie -------------------------------------
outDir = pwd;
if ~exist(outDir, 'dir'), mkdir(outDir); end

%% --- Journal des combinaisons ---------------------------------
logFile = fullfile(outDir, 'sweep_PV_CC_log.csv');
fid = fopen(logFile, 'w');
fprintf(fid, 'Model_name,Ppv_pu,Pcc_pu,V_pu,angle_deg,status\n');

%% --- Compteur global ------------------------------------------
nTotal = length(Ppv_vec) * length(Pcc_vec);
nDone  = 0;
fprintf('\n=== Démarrage du sweep PV_CC : %d combinaisons ===\n\n', nTotal);

%% --- Boucle principale ----------------------------------------
for iPv = 1:numel(Ppv_vec)
for iCc = 1:numel(Pcc_vec)
    
    % -- Valeurs courantes du point de fonctionnement --
    Ppv_val = Ppv_vec(iPv);
    Pcc_val = Pcc_vec(iCc);
    
    nDone = nDone + 1;
    fprintf('[%d/%d] Ppv = %.1f pu | Pcc = %.1f pu\n', nDone, nTotal, Ppv_val, Pcc_val);
    
    % -- Nom unique du nouveau modèle --
    strPpv = strrep(sprintf('%.1f', Ppv_val), '.', 'p');
    strPcc = strrep(sprintf('%.1f', Pcc_val), '.', 'p');
    newName = sprintf('%s_Ppv%s_Pcc%s', baseModel, strPpv, strPcc);
    
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
        % Le script 'LoadFlow_VSC' a besoin des valeurs réelles dans le Workspace
        assignin('base', 'Ppv', Ppv_val);
        assignin('base', 'Pcc', Pcc_val);
        
        %% 3) Exécution du Load Flow --------------------------
        % /!\ Cette étape va temporairement écraser les champs P0 des blocs avec les valeurs numériques
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
        % Maintenant que le Load Flow a fini ses calculs et ses modifications,
        % on ré-injecte les chaînes de caractères afin que le modèle sauvegardé dépende du GA.
        
        % Configuration du bloc PV (GFL IDEAL VSC)
        blocPV = [newName, '/GFL IDEAL VSC'];
        set_param(blocPV, 'P0', 'Ppv'); 
        fprintf('   ✔ Bloc PV restauré dynamiquement avec la variable : ''Ppv''\n');
        
        % Configuration du bloc CC (GFM_CC IDEAL_VSC1)
        blocCC = [newName, '/GFM_CC IDEAL_VSC1']; 
        set_param(blocCC, 'P0', 'Pcc'); 
        fprintf('   ✔ Bloc CC restauré dynamiquement avec la variable : ''Pcc''\n');
        
        %% 5) Sauvegarde du modèle initialisé -----------------
        save_system(newName, newPath);
        close_system(newName, 0);
        fprintf('   ✔ Modèle sauvegardé avec succès : %s\n\n', newPath);
        
    catch ME
        status = ME.message;
        warning('   ✘ Erreur [%d/%d] : %s\n', nDone, nTotal, ME.message);
        if bdIsLoaded(newName), close_system(newName, 0); end
    end
    
    % -- Journalisation CSV --
    fprintf(fid, '%s,%.2f,%.2f,%.4f,%.4f,%s\n', ...
            newName, Ppv_val, Pcc_val, V_amplitude_pu, V_phase_deg, status);
end % iCc
end % iPv

%% --- Clôture --------------------------------------------------
fclose(fid);
fprintf('=== Sweep terminé (%d combinaisons). Journal : %s ===\n', nTotal, logFile);