classdef Channel

    properties
        tgnChannel
        SNR
    end

    methods
        function obj = Channel(Model, dist, Fc, Fs, SNR)
            tgnChannel = wlanTGnChannel;
            tgnChannel.DelayProfile             = Model; 
            tgnChannel.NumTransmitAntennas      = 1;         
            tgnChannel.NumReceiveAntennas       = 1;         
            tgnChannel.TransmitReceiveDistance  = dist;    
            tgnChannel.LargeScaleFadingEffect   = 'None';
            tgnChannel.NormalizeChannelOutputs  = false;
            tgnChannel.CarrierFrequency         = Fc;
            tgnChannel.SampleRate               = Fs;  


            obj.tgnChannel = tgnChannel;
            obj.SNR = SNR;
        end

        function rx_waveform = tx(obj, tx_waveform)
            waveform = [zeros(size(tx_waveform)); tx_waveform; zeros(size(tx_waveform))];
            waveform = obj.tgnChannel(waveform);
            waveform = awgn(waveform,obj.SNR,'measured');
            rx_waveform = waveform;
        end

    end
end