classdef Channel

    properties
        tgnChannel
        SNR
        cfo_shifter
        p_noise
        max_random_sto
    end

    methods
        function obj = Channel(options)
            arguments
                options.Model = 'Model-A'
                options.dist = 10
                options.Fc = 2.4e9 
                options.Fs = 20e6 
                options.SNR = 100
                options.CFO = 0
                options.PhaseNoiseLevel = [-50 -80 -100] 
                options.PhaseNoiseFreq  = [100 1000 10000]
                options.max_random_sto = 1
            end

            tgnChannel = wlanTGnChannel;
            tgnChannel.DelayProfile             = options.Model; 
            tgnChannel.NumTransmitAntennas      = 1;         
            tgnChannel.NumReceiveAntennas       = 1;         
            tgnChannel.TransmitReceiveDistance  = options.dist;    
            tgnChannel.LargeScaleFadingEffect   = 'None';
            tgnChannel.NormalizeChannelOutputs  = false;
            tgnChannel.CarrierFrequency         = options.Fc;
            tgnChannel.SampleRate               = options.Fs;  

            obj.tgnChannel = tgnChannel;

            obj.cfo_shifter = comm.PhaseFrequencyOffset(...
                'FrequencyOffset', options.CFO, ...
                'SampleRate', options.Fs);

           obj.p_noise = comm.PhaseNoise(...
                'Level', options.PhaseNoiseLevel, ...
                'FrequencyOffset', options.PhaseNoiseFreq, ...
                'SampleRate', options.Fs);

            obj.SNR = options.SNR;
            obj.max_random_sto = options.max_random_sto;
        end

        function rx_waveform = tx(obj, tx_waveform)


            if obj.max_random_sto > 0 
                waveform = [
                    zeros(1000,1); 
                    zeros(randi(obj.max_random_sto), 1); 
                    tx_waveform; 
                    zeros(1000,1)
                ];
            else
                waveform = [
                    zeros(1000,1); 
                    tx_waveform; 
                    zeros(1000,1)
                ];
            end

            waveform = obj.tgnChannel(waveform);
            waveform = obj.cfo_shifter(waveform);
            % waveform = obj.p_noise(waveform);
            waveform = awgn(waveform,obj.SNR,'measured');
            rx_waveform = waveform;
        end

    end
end