
%%%%%%%%%% Channel Model %%%%%%%%%%
Model   = 'Model-B';
dist    = 10;
Fc      = 2.4e9;
Fs      = 20e6;
SNR     = 10;

chan = Channel(Model, dist, Fc, Fs, SNR);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%% Frame format %%%%%%%%%%
N       = 1024; % num subcarriers
L       = 32;   % cycle extention
Npil    = 4;    % pilot num
NumFr   = 5;    % num data frames

seq_frames = [1 4; 2 10; 3 NumFr]; % message format
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

stf = STF(N,L,[0.25*N, 0.75*N]+1, seq_frames(1,2), 3, 1);

rx_waveform = chan.tx(stf.waveform);

% plot(real(rx_waveform));
% plot(abs(fftshift(fft(rx_waveform))));


