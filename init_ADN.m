%% Step Time %%
Ts = 50e-6;
Tf = 0.5; % Fault time

% Nominal Frequency (Hz)
fn = 50;   % Nominal frequency [Hz] 
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
Rg_pu = Lg_pu*(wn/wb)/10;
Lg = Lg_pu*Lb;
Rg = Rg_pu*Zb;


%% Converters
Sn_GFM_2 = 6e3;
Sn_GFL_3 = 3e3;
Sn_GFL_4 = 4e3;
Vdc = 640;

Vnvsc = 320;

%% Control parameters 
% --- GFM2 --- %
H_2 = 2;          %This param will be estimated
ksi_2 = 1;        %This param will be estimated
DelayGFM = 120e-6;
% vcGFM
Rv_GFM_2 = 0.15;  %This param will be estimated (originally 0.09)
W_TVR = 60;

% --- GFL3 -- %
wi_3 = 1800;
wff_3 = 2200;
DelayGFL = 120e-6;
wpll_3 = 950;     %This param will be estimated
wp_3 = 30;        %This param will be estimated
%pvGFL
wv_3 = 9;

% --- GFL4 -- %
wi_4 = 1600;
wff_4 = 1600;
% DelayGFL = 120e-6;
wpll_4 = 650;     %This param will be estimated
wp_4 = 14;        %This param will be estimated
%pvGFL
wv_4 = 12;


%% Lines
r = 0.4;    % Omh/km
x = 0.12;   % Omh/km

l_12 = 0.1; % km
R_12 = r*l_12;
L_12 = (x*l_12)/wb;

l_23 = 0.05; % km
R_23 = r*l_23;
L_23 = (x*l_23)/wb;

l_34 = 0.06; % km
R_34 = r*l_34;
L_34 = (x*l_34)/wb;

l_35 = 0.01; % km
R_35 = r*l_35;
L_35 = (x*l_35)/wb;


%% Initial disturbances
% delta_P_GFL = 0.0;
% delta_P_GFM = 0.0;
delta_E = 0;
delta_theta_deg = 0;
enable_breaker = 1;
P_fault = 0.2*Sng;
Q_fault = 0;