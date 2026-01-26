clc;

Fc = 2.8e9;
Fs = 5e6;

STA1 = py.sdr.SDR( ...
    'ip:192.168.3.1', ...
    Fc, ...
    Fs, ...
    tx_cycle_buffer = false, ...
    buffer_size = 65536, ...
    tx_hardwaregain_chan0 = 0, ...
    rx_hardwaregain_chan0 = 50);


STA2 = py.sdr.SDR( ...
    'ip:192.168.4.1', ...
    Fc, ...
    Fs, ...
    buffer_size = STA1.buffer_size*100, ...
    tx_hardwaregain_chan0 = 0, ...
    rx_hardwaregain_chan0 = 50);


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
            det_mask_width = 30, ...
            det_threshold = 3.0); %dB

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
            beta=0.2, ...
            debug=true);

%==========================================================================

% Init Reciever ===========================================================
    stf_handler = STF_Handler( ...
        stf, ...
        debug=false);

    ltf_handler = LTF_Handler( ...
        ltf, ...
        h_window=4*L, ...
        debug=true);
%==========================================================================

% Frame generation 
    fprintf("Gen data\n");
    source = randi([0,1], data_handler.payload, 1);
    data_waveform = data_handler.get_waveform(source);
    tx_waveform = vertcat(stf.waveform, ltf.waveform, data_waveform);

% Channel
    fprintf("Send data\n");
    tx_waveform = tx_waveform.*2^12;

    figure(1);
    clf;
    subplot(2,1,1);
    plot(abs(tx_waveform));

    subplot(2,1,2);
    spectrogram(tx_waveform, N, [], 'yaxis', 'centered');
    max_val = max(db(tx_waveform));
    clim([max_val-50, max_val]);

    tx_waveform = tx_waveform.';
    tx_waveform_with_zeros = [zeros(1,50*STA1.buffer_size), tx_waveform];

    STA1.send(tx_waveform_with_zeros);
    rx_waveform = reshape(double(STA2.recv()), [], 1);
    
    fprintf("Receive data\n");

    figure(2);
    clf;
    subplot(2,1,1);
    plot(abs(rx_waveform));

    subplot(2,1,2);
    spectrogram(rx_waveform, N, [], 'yaxis', 'centered');
    max_val = max(db(rx_waveform));
    clim([max_val-50, max_val]);



% state 1 - stf
    detect = stf_handler.detect(rx_waveform);
    fprintf("SNR: %f\n", stf_handler.snr);

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

figure(3);
clf;
t = tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
val = db(rx_waveform);
max_val = max(val);
spectrogram(rx_waveform, N, [], 'yaxis', 'centered');
clim([max_val-40, max_val+10]);


ifft_data = ifft_data./sqrt(mean(abs(ifft_data.^2)));

nexttile;
s1 = scatter(real(ifft_data(:)), imag(ifft_data(:)), 3, 'blue', 'filled');
s1.MarkerFaceAlpha = 0.1; 
s1.MarkerEdgeAlpha = 0.1; 
hold("on");

% Исправлено: убрано c='.', добавлен цвет и 'filled'
s2 = scatter(real(rx_eqv_data(:).'), imag(rx_eqv_data(:).'), 3, 'red', 'filled');
s2.MarkerFaceAlpha = 1;
s2.MarkerEdgeAlpha = 1; 

% Исправлено: убрано c='.', добавлен цвет и 'filled'
s3 = scatter(real(rx_eqv_pilots(:).'), imag(rx_eqv_pilots(:).'), 7, 'green', 'filled');
s3.MarkerFaceAlpha = 0.1;
s3.MarkerEdgeAlpha = 0.1; 

grid("on");
xlim([-2, 2]);
ylim([-2, 2]);
axis("square");

delete(findobj(gcf, 'Type', 'uicontrol'));

% --- Элементы управления ---

% 1. IFFT Data (Blue)
txt = uicontrol('Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.55 0.97 0.1 0.03], ...
    'String', 'ifft data: 0.10');

ifft_sld = uicontrol('Style', 'slider', ...
    'Min', 0, 'Max', 1, 'Value', 0.1, ...
    'Units', 'normalized', ...
    'Position', [0.55 0.95 0.1 0.03], ...
    'Callback', @(src, event) updateAlpha(src, s1, txt, 'ifft data')); 

% 2. EQV Data (Red)
data_txt = uicontrol('Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.65 0.97 0.1 0.03], ...
    'String', 'eqv data: 1.00');

data_sld = uicontrol('Style', 'slider', ...
    'Min', 0, 'Max', 1, 'Value', 1, ...
    'Units', 'normalized', ...
    'Position', [0.65 0.95 0.1 0.03], ...
    'Callback', @(src, event) updateAlpha(src, s2, data_txt, 'eqv data')); 

% 3. Pilots (Green)
pil_txt = uicontrol('Style', 'text', ...
    'Units', 'normalized', ...
    'Position', [0.75 0.97 0.1 0.03], ...
    'String', 'pilots: 0.10');

pil_sld = uicontrol('Style', 'slider', ...
    'Min', 0, 'Max', 1, 'Value', 0.1, ...
    'Units', 'normalized', ...
    'Position', [0.75 0.95 0.1 0.03], ...
    'Callback', @(src, event) updateAlpha(src, s3, pil_txt, 'pilots')); 


% --- Функция обновления ---
function updateAlpha(slider, plotObject, textHandle, labelName)
    val = slider.Value;
    
    % Обновляем прозрачность
    plotObject.MarkerFaceAlpha = val;
    plotObject.MarkerEdgeAlpha = val;
    
    % Обновляем конкретный текст
    textHandle.String = sprintf('%s: %.2f', labelName, val);
    
    drawnow limitrate; 
end