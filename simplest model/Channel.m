classdef Channel

    properties
        tgnChannel
        SNR
        cfo_shifter
        cfo
        p_noise
        max_random_sto
        awgn_only
        rndStream
        seed
    end

    methods
        function obj = Channel(options)
            arguments
                options.Model = 'Model-A'
                options.dist = 100
                options.Fc = 2.4e9 
                options.Fs = 20e6 
                options.SNR = 100
                options.CFO = 0
                options.PhaseNoiseLevel = [-50 -80 -100] 
                options.PhaseNoiseFreq  = [100 1000 10000]
                options.max_random_sto = 1
                options.awgn_only = false

                options.Seed = 0
            end

            obj.rndStream = RandStream('mt19937ar', 'Seed', options.Seed);
            obj.seed = options.Seed;

            if options.Model == "awgn"
                options.awgn_only = true;
            else
                tgnChannel = wlanTGnChannel;
                tgnChannel.DelayProfile             = options.Model; 
                tgnChannel.NumTransmitAntennas      = 1;         
                tgnChannel.NumReceiveAntennas       = 1;         
                tgnChannel.TransmitReceiveDistance  = options.dist;    
                tgnChannel.LargeScaleFadingEffect   = 'None';
                tgnChannel.NormalizeChannelOutputs  = false;
                tgnChannel.CarrierFrequency         = options.Fc;
                tgnChannel.SampleRate               = options.Fs;  

                tgnChannel.RandomStream = 'mt19937ar with seed';
                tgnChannel.Seed = options.Seed;
    
                obj.tgnChannel = tgnChannel;
            end

            obj.cfo = options.CFO;
            obj.cfo_shifter = comm.PhaseFrequencyOffset(...
                'FrequencyOffset', options.CFO, ...
                'SampleRate', options.Fs);

           obj.p_noise = comm.PhaseNoise(...
                'Level', options.PhaseNoiseLevel, ...
                'FrequencyOffset', options.PhaseNoiseFreq, ...
                'SampleRate', options.Fs);

            obj.SNR = options.SNR;
            obj.max_random_sto = options.max_random_sto;
            obj.awgn_only = options.awgn_only;
        end

        function rx_waveform = tx(obj, tx_waveform)
            
            reset(obj.rndStream);
            if obj.max_random_sto > 0 
                waveform = [
                    zeros(100,1); 
                    zeros(randi(obj.rndStream, obj.max_random_sto), 1); 
                    tx_waveform; 
                    zeros(100,1)
                ];
            else
                waveform = [
                    zeros(100,1); 
                    tx_waveform; 
                    zeros(100,1)
                ];
            end
            
            if ~obj.awgn_only
                % reset(obj.tgnChannel);
                waveform = obj.tgnChannel(waveform);

                if obj.cfo
                    waveform = obj.cfo_shifter(waveform);
                end
            end
            % waveform = obj.p_noise(waveform);
            
            if obj.seed>0
                waveform = awgn(waveform, obj.SNR, 0, obj.rndStream);
            else
                waveform = awgn(waveform, obj.SNR);
            end
            
            rx_waveform = waveform;
        end

    end
end