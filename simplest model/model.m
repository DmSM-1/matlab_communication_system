clc;

% Channel Model ===========================================================
    chan = Channel( ...
        Model='Model-A', ...
        dist=10, ...
        Fc=2.4e9, ...
        Fs=20e6, ...
        SNR=10, ...
        CFO=1000, ...
        max_random_sto=1000);
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
        Mod_pow = 1;
        Nsymb   = 1;
        Npil    = 8;
        Cod_rate= 1;
        Ndat    = 768;

        NumGuardBandCarriers = (N-Ndat-Npil-1);

        ofdmMod = comm.OFDMModulator( ...
            'FFTLength', N, ...
            'NumGuardBandCarriers', [floor(NumGuardBandCarriers/2);ceil(NumGuardBandCarriers/2)], ...
            'InsertDCNull', true, ...
            'CyclicPrefixLength', L, ...
            'Windowing', false, ...
            'OversamplingFactor', 1, ...
            'NumSymbols', Nsymb, ...
            'NumTransmitAntennas', 1, ...
            'PilotInputPort', true ...
            );
        
        ofdmDemod = comm.OFDMDemodulator( ...
            'FFTLength', N, ...
            'NumGuardBandCarriers', [floor(NumGuardBandCarriers/2);ceil(NumGuardBandCarriers/2)], ...
            'RemoveDCCarrier', true, ...
            'CyclicPrefixLength', L, ...
            'OversamplingFactor', 1, ...
            'NumSymbols', Nsymb, ...
            'NumReceiveAntennas', 1, ...
            'PilotOutputPort', false ...
            );

        left_guard = floor(NumGuardBandCarriers/2);
        right_guard   = N-ceil(NumGuardBandCarriers/2);
        pilot_dist  = floor((N-NumGuardBandCarriers-1)/(Npil-1));
        
        pilotIdx = left_guard+1:pilot_dist:right_guard;
        pilotIdx(floor(Npil/2)+1:end) = pilotIdx(floor(Npil/2)+1:end)+mod(Ndat+Npil, pilot_dist);
        
        ofdmMod.PilotCarrierIndices = pilotIdx.';

        pilots = pskmod(zeros(Nsymb, Npil), 2);
        payload = floor(Nsymb*Ndat*Cod_rate*Mod_pow*Cod_rate);

        SOURCE = randi([0,1], payload, 1);

        MOD_DATA = qammod(SOURCE, 2^Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
        MOD_DATA = reshape(MOD_DATA, Nsymb, Ndat);
        data_waveform = ofdmMod(MOD_DATA.', pilots.');
        data_waveform = data_waveform./sqrt((mean(abs(data_waveform.^2))));

%==========================================================================

% Init Reciever
    stf_handler = STF_Handler( ...
        stf, ...
        debug=false);

    ltf_handler = LTF_Handler( ...
        ltf, ...
        h_window=4*L, ...
        debug=true);

% Frame generation 
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
    
    rx_data_symbs = ofdmDemod(rx_data_waveform);

    % for i = 1:size(rx_data_symbs)
    % rx_data_symbs = rx_data_symbs./ltf_handler.H;


% Graphs ==================================================================
    figure(1);
    clf;
    subplot(2,1,1)
    plot(real(rx_waveform));
    
    subplot(2,1,2)
    spectrogram(rx_waveform, N, [], 'yaxis', 'centered');
    max_val = max(db(rx_waveform));
    clim([max_val-50, max_val]);
    
    figure(2)
    clf;
    plot(abs(fftshift(fft(rx_waveform))));
    
    figure(3);
    clf;
    subplot(2,1,1)
    plot(real(rx_detected_frame));
    
    subplot(2,1,2)
    spectrogram(rx_detected_frame, N, [], 'yaxis', 'centered');
    max_val = max(db(rx_detected_frame));
    clim([max_val-50, max_val]);

    figure(4);
    clf;

    % subplot(2,1,1)
    disp(size(rx_data_symbs(:)));
    scatter(real(rx_data_symbs(:).'), imag(rx_data_symbs(:).'), c='.');

