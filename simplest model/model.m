clc;

% Channel Model ===========================================================
    chan = Channel( ...
        Model='Model-B', ...
        dist=10, ...
        Fc=2.4e9, ...
        Fs=20e6, ...
        SNR=30, ... %что то здесь не так
        CFO=1000);
%==========================================================================

% Frame format ============================================================
    N       = 1024; % num subcarriers
    L       = 32;   % cycle extention
    Npil    = 4;    % pilot num
    Nsymb   = 5;    % num data symbols
    
    % STF format
        stf = STF( ...
            N,L, ...
            Ppos = [0.25, 0.75]*N+1, ...
            margin1 = 1, ...
            est_symb = 4, ...
            margin2 = 1, ...
            det_mask_width = 5, ...
            det_threshold = 10.0); %dB
%==========================================================================

% Init Reciever ===========================================================
    stf_detector = STF_Detector(stf, debug=false);
%==========================================================================


rx_waveform = chan.tx(stf.waveform);

detect = stf_detector.detect(rx_waveform);

fprintf("Frame detected: %d\n", detect);

figure(1);
clf;
spectrogram(rx_waveform, 'yaxis', N);

figure(2);
clf;
subplot(2,1,1)
plot(real(rx_waveform));

subplot(2,1,2)
plot(abs(fftshift(fft(rx_waveform))));

t = 0:length(rx_waveform)-1;
t = t.';
rx_waveform = rx_waveform.*exp(-2i*pi*stf_detector.cfo*t);

figure(3);
clf;
subplot(2,1,1)
plot(real(rx_waveform));

subplot(2,1,2)
plot(abs(fftshift(fft(rx_waveform))));



