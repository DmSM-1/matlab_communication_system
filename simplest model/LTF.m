classdef LTF


    properties
        N
        L
        bw
        symb_len
        Nsymb
        waveform
        ref
        sto_shift
    end

    methods
        function obj = LTF(N, L, options)
            arguments
                N 
                L 
                options.Nsymb = 4
                options.sto_shift = 0
                options.bw = 1.0
            end
            
            obj.N = N;
            obj.L = L;
            obj.bw = options.bw;
            obj.symb_len = N+L;
            obj.Nsymb = options.Nsymb;
            obj.waveform = complex(zeros(obj.Nsymb*obj.symb_len, 1));
            obj.sto_shift = options.sto_shift;

            if obj.Nsymb < 4 || mod(obj.Nsymb,2) 
                error('LTF:Invalid Nsymb', 'LTF:Invalid Nsymb');
            end

            sample = 0;

            for i = 1:length(obj.waveform)

                obj.waveform(i) = exp(1i*pi*sample^2/(2*N)); %2T
                sample = sample+1;

                if sample == 2*N
                    sample = 0;
                end
            end   

            obj.ref = obj.waveform(1:2*N);
        end
    end
end