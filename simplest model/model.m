clc;

% Channel Model ===========================================================
    chan = Channel( ...
        Model='Model-B', ...
        dist=10, ...
        Fc=2.4e9, ...
        Fs=20e6, ...
        SNR=30, ...
        CFO=1000, ...
        max_random_sto=10000);
%==========================================================================

% Frame format ============================================================
    N       = 1024; % num subcarriers
    L       = 32;   % cycle extention
    
    % STF format
        stf = STF( ...
            N,L, ...
            Ppos = [0.25, 0.75]*N+1, ...
            margin1 = 1, ...
            est_symb = 4, ...
            margin2 = 1, ...
            det_mask_width = 5, ...
            det_threshold = 10.0); %dB

    % LTF format
        ltf = LTF( ...
            N, L, ...
            Nsymb = 8);

    % Data format
        data_handler = DATA_Handler( ...
            N=N, ...
            L=L, ...
            Ndat=512, ...
            Npil=8, ...
            Nsymb=2000, ...
            Mod_pow=4, ...
            Cod_rate=1, ...
            alpha=0.5, ...
            beta=0.5, ...
            debug=true);

%==========================================================================

% Init Reciever ===========================================================
    stf_handler = STF_Handler( ...
        stf, ...
        debug=false);

    ltf_handler = LTF_Handler( ...
        ltf, ...
        h_window=4*L, ...
        debug=false);
%==========================================================================

% Frame generation 
    source = randi([0,1], data_handler.payload, 1);
    data_waveform = data_handler.get_waveform(source);
    tx_waveform = vertcat(stf.waveform, ltf.waveform, data_waveform);

% Channel simulation
    rx_waveform = chan.tx(tx_waveform);

% state 1 - stf
    detect = stf_handler.detect(rx_waveform);
    
    rx_detected_frame = rx_waveform(stf_handler.sto:min(length(rx_waveform), stf_handler.sto+length(tx_waveform)));
    t = 0:length(rx_detected_frame)-1;
    t = t.';
    rx_detected_frame = rx_detected_frame.*exp(-2i*pi*stf_handler.cfo*t);

% state 2 - ltf
    est = ltf_handler.estimate(rx_detected_frame);
    ltf_handler.sto = ltf_handler.sto;
    rx_data_waveform = rx_detected_frame(ltf_handler.sto:ltf_handler.sto+length(data_waveform)-1);
    
% state 3 - data
    eqv = data_handler.set_eqv(ltf_handler);
    [ifft_data, rx_res_data, rx_eqv_data, rx_eqv_pilots] = data_handler.get_data(rx_data_waveform);

% Results =================================================================
ber  = mean(xor(rx_res_data, data_handler.data));
rmse = sqrt(mean(abs(rx_eqv_data(:)-data_handler.mod_data(:)).^2));

fprintf("BER:  %f\nRMSE: %f\n", ber, rmse);

figure(1);
clf;
t = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
spectrogram(rx_waveform, N, [], 'yaxis', 'centered');
max_val = max(db(rx_waveform));
clim([max_val-50, max_val]);

ifft_data = ifft_data./sqrt(mean(abs(ifft_data.^2)));

nexttile;
scatter(real(ifft_data(:)), imag(ifft_data(:)), 3, 'blue', c='.');
hold("on");
scatter(real(rx_eqv_data(:).'), imag(rx_eqv_data(:).'), 3, 'red', c='.');
hold("on");
scatter(real(rx_eqv_pilots(:).'), imag(rx_eqv_pilots(:).'), 7, 'green', c='.');

xlim([-2, 2]);
ylim([-2, 2]);
axis("square");
