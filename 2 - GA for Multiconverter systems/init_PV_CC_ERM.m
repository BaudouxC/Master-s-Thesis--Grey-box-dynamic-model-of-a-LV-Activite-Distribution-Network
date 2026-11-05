%% Step Time %%
Ts = 50e-6;
% Time_Step = Ts;
Tf = 0.5; % Fault time

% Nominal Frequency (Hz)
fn = 50;   % Nominal frequency [Hz] 
fb = 50;
wn = 2*pi*fn;
wb = wn;

% Nominal Power (V)
Un = 400; % ph2ph
Vn = Un/sqrt(3); % ph2g


%% Grid parameters %%
Sng = 1e5; % 100 kVA

% perunitage
Zb = Un^2/Sng;
Lb = Zb/wb;

%  Grid strength
SCR = 3;
Lg_pu = 1/SCR;
Rg_pu = (Lg_pu*(wn/wb))/10;
Lg = Lg_pu*Lb;
Rg = Rg_pu*Zb;


%% Converters
Sn_pqGFL = 10e3;
Sn_pvGFL = 10e3;
Sn_vcGFM = 10e3;
Sn_ccGFM = 10e3;
Vdc = 640;
Vnvsc = 320;


%% Control parameters 
% --- pqGFL -- %
wipq = 2000;
wffpq = 2000;
Delaypq = 120e-6;
wpllpq = 700;
wppq = 25;
Ppq = 0.5;

% --- pvGFL -- %
wipv = 2000;
wffpv = 2000;
Delaypv = 120e-6;
wpllpv = 700;
wppv = 25;
wvpv = 9;
Ppv = 0.5;

% --- vcGFM --- %
Hvc = 2;
ksivc = 1;
Delayvc = 120e-6;
Rvvc = 0.15;
W_TVRvc = 60;
Pvc = 0.5;

% --- ccGFM --- %
Hcc = 2;
ksicc = 1;
wicc = 2000;
wffcc = 2000;
Delaycc = 120e-6;
wQSEMvcc = 63;
Pcc= 0.5;

% --- ERM (Exponential Recovery Model) --- %
P_ERM = 10e3;
Q_ERM = 1e3;

% Paramètres Actifs (P)
Nps = 0.5;     % Exposant statique (souvent entre 0 et 1 pour une charge mixte)
Npt = 2.0;     % Exposant transitoire (proche de 2 : se comporte comme une impédance au choc)
Tp  = 0.5;     % Temps de récupération actif (souvent entre 0.1s et 1.5s)

% Paramètres Réactifs (Q)
Nqs = 1.5;     % Exposant statique réactif (souvent plus élevé que l'actif)
Nqt = 2.0;     % Exposant transitoire réactif (impédance constante au choc)
Tq  = 0.5;     % Temps de récupération réactif (souvent similaire à Tp)


%% Initial disturbances
delta_E = 0;
delta_theta_deg = 0;
enable_breaker = 0;
P_fault = 1e3;
Q_fault = 0;