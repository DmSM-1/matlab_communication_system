close all;
clear; 
% clc;

dataset_path = "ber_snr_test";

runs = 3;
k = 2;
names           = ["ML","ML1","ML2","ML3"];
metric          = ["ML","ML1","ML2","ML3"];
est_method      = ("LS");
Nvpil           = [64];





sim = ofdm_simulator( ...
    OutputDir       = dataset_path, ...
    ...
    SNR             = 20, ...  
    ChanModel       = "awgn", ... %"Model-A" "awgn"
    ...
    N               = 1024, ...
    L               = 256, ...
    Mod_pow         = k, ...   
    Cod_rate        = 0.5, ...
    Bw              = 0.9, ... 
    Npil            = 8, ...
    pilAmpl         = 2.0, ...
    DC_guard        = 64, ...
    data_Nsymb      = 1000, ...
    ...
    Fc              = 3.1e9, ...
    Fs              = 5e6, ...
    sdr_gain        = 2^12, ...
    sdr_order       = 0, ...
    ...
    stf_est_symb    = 128, ...
    ltf_Nsymb       = 128, ...
    ...
    graph_output    = [1,2], ...
    ...
    ltf_sto_shift   = -128, ...
    h_len           = 16, ...
    est_period      = 1, ...
    ...
    names           = names, ... %"Nvp0", "Nvp16", "Nvp32", "Nvp64", "Nvp128", "NvpAll"
    alpha           = (0.1), ...
    beta            = (0.2), ...
    soft            = (1), ...
    Nvpil           = Nvpil, ...
    est_method      = est_method, ...
    metric          = metric, ...
    audio           = 0, ...
    audio_path="FlyMeToTheMoon_mono.wav" ...
);


% if exist(dataset_path, 'dir')
%    rmdir(dataset_path, 's');
% end
% sim.generate_dataset(runs, "seed", 1:runs);
% snr = 24:-3:0;
% power = 2.^(11:0.25:12.5);
% for i = power
%     % sim.snr = i;
%     % sim.chan.SNR = i;
%     sim.sdr_gain = i;
%     % sim.run_channel_on_dataset();
% 
%     sim.run_sdr_channel_on_dataset();
%     sim.process_dataset();
% end


bw = (sim.data_handler.ofdm.Ndat+sim.data_handler.ofdm.Npil)/sim.data_handler.ofdm.N;
filename = dataset_path+'/statistics.csv';
csv = readtable(filename, 'ReadRowNames', true);

data = csv(csv.MOD_POW==k,:);
data = data(1:size(data,1)-mod(size(data,1), runs), :);

ber = csv(:, 4:3:end);
fber = csv(:, 5:3:end);
mse = csv(:, 6:3:end);

snr = csv(:, 3);
snr = mean(reshape(snr.Variables, runs, []));
snr = snr-10*log10(bw)-10*log10(k);

ber = reshape(mean(reshape(ber.Variables, runs, length(snr), [])), length(snr), []);
fber = reshape(mean(reshape(fber.Variables, runs, length(snr), [])), length(snr), []);
mse = reshape(mean(reshape(mse.Variables, runs, length(snr), [])), length(snr), []);

t_snr = linspace(min(snr), max(snr), 100);
t_ber = (berawgn(snr, 'qam', 2^k));


color1 = [0 0.4470 0.7410];   
color2 = [0.8500 0.3250 0.0980]; 
color3 = [0.4660 0.6740 0.1880];
color4 = [0.6350 0.0780 0.1840];

lineWidth = 2;
markerSize = 10;
markerStep = 4;

color = [color1; color2; color3; color4];
Marker = ['^', 'v', 'o', 's'];


f = figure(4);
clf;
f.Theme = "light";
h0 = semilogy(snr, t_ber, Color=[0 0 0]);
h = [];

for i = 1:length(names)
    hold on;
    g = semilogy(snr, ber(:, i), ...
        'Color', color(i, :), ...
        'Marker', Marker(i), ...
        'MarkerSize', markerSize, ...
        'MarkerFaceColor', color(i, :), ...
        'MarkerEdgeColor', 'w');
    h = [h; g];
end

grid on;
ax = gca;

ax.GridLineStyle  = '-';          
ax.GridColor      = [0.6 0.6 0.6];
ax.GridAlpha      = 1;            
ax.GridLineWidth  = 0.8;    

ax.MinorGridColor = [0.8 0.8 0.8];
ax.MinorGridAlpha = 0.7;

legend([h0; h], ["theory", names], 'Location', 'southwest');

f = figure(5);
clf;
f.Theme = "light";

h = [];

for i = 1:length(names)
    g = semilogy(snr, mse(:, i), ...
        'Color', color(i, :), ...
        'Marker', Marker(i), ...
        'MarkerSize', markerSize, ...
        'MarkerFaceColor', color(i, :), ...
        'MarkerEdgeColor', 'w');
    hold on;
    h = [h; g];
end

grid on;
ax = gca;

ax.GridLineStyle  = '-';          
ax.GridColor      = [0.6 0.6 0.6];
ax.GridAlpha      = 1;            
ax.GridLineWidth  = 0.8;    

ax.MinorGridColor = [0.8 0.8 0.8];
ax.MinorGridAlpha = 0.7;

legend(h, names, 'Location', 'southwest');

f = figure(6);
clf;
f.Theme = "light";

h = [];


rel_ber = ber(:, 1)./ber;

for i = 1:length(names)
    g = semilogy(snr, rel_ber(:, i), ...
        'Color', color(i, :), ...
        'Marker', Marker(i), ...
        'MarkerSize', markerSize, ...
        'MarkerFaceColor', color(i, :), ...
        'MarkerEdgeColor', 'w');
    hold on;
    h = [h; g];
end

grid on;
ax = gca;

ax.GridLineStyle  = '-';          
ax.GridColor      = [0.6 0.6 0.6];
ax.GridAlpha      = 1;            
ax.GridLineWidth  = 0.8;    

ax.MinorGridColor = [0.8 0.8 0.8];
ax.MinorGridAlpha = 0.7;

legend(h, names, 'Location', 'southwest');


f = figure(7);
clf;
f.Theme = "light";

h = [];


rel_mse = mse(:, 1)./mse;

for i = 1:length(names)
    g = semilogy(snr, rel_mse(:, i), ...
        'Color', color(i, :), ...
        'Marker', Marker(i), ...
        'MarkerSize', markerSize, ...
        'MarkerFaceColor', color(i, :), ...
        'MarkerEdgeColor', 'w');
    hold on;
    h = [h; g];
end

grid on;
ax = gca;

ax.GridLineStyle  = '-';          
ax.GridColor      = [0.6 0.6 0.6];
ax.GridAlpha      = 1;            
ax.GridLineWidth  = 0.8;    

ax.MinorGridColor = [0.8 0.8 0.8];
ax.MinorGridAlpha = 0.7;

legend(h, names, 'Location', 'southwest');