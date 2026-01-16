classdef LTF_Handler < handle
    
    properties
        ltf
        sto
        h
        H
        eqv
        h_window
        debug
    end

    methods
        function obj = LTF_Handler(ltf, options)
            arguments
                ltf 
                options.h_window = ltf.L;
                options.debug = false;
            end

            obj.ltf = ltf;
            obj.sto = 0;
            obj.h = [];
            obj.H = [];
            obj.eqv = [];
            obj.h_window = options.h_window;
            obj.debug = options.debug;
        end

        function est = estimate(obj, waveform)
            arguments
                obj 
                waveform 
            end
            
            buf = waveform(1:2*obj.ltf.N);
            obj.H = fft(buf)./fft(obj.ltf.ref);
            obj.h = ifft(obj.H);

            [max_val, max_index] = max(abs(obj.h));

            if obj.debug
                fprintf("Start  estimation\n");

                figure(200);
                clf;

                subplot(2,1,1)
                plot(real(buf));
                hold("on");

                plot(abs(obj.h));

                subplot(2,1,2);
                plot(abs(obj.h));

                fprintf("Max val: %f index %d\n", max_val, max_index);
            end

            obj.sto = max_index+length(obj.ltf.waveform);

            buf = waveform(max_index+1+2*obj.ltf.N:max_index+4*obj.ltf.N);
            obj.H = fft(buf)./fft(obj.ltf.ref);
            obj.h = ifft(obj.H);

            [max_val, max_index] = max(abs(obj.h));
            
            disp(obj.h_window);
            obj.h(obj.h_window/2+1:end-obj.h_window) = 0;
            obj.H = fft(obj.h);
            obj.H = obj.H(1:2:end);

            if obj.debug
                figure(201);

                subplot(2,1,1);
                plot(abs(obj.h));

                subplot(2,1,2);
                val = abs(fftshift(obj.H));
                val = (val/max(val));
                plot(val);
                ylim([0, 1]);
            end
                      
            obj.eqv = 1/(obj.H+1e-6);
            
            est = true;
        end

    end
end