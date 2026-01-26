classdef STF_Handler < handle

    % State machine =======================================================
    % 0 - detect stf
    % 1 - est gain   
    % 2 - wait margin
    % 3 - cfo estimate
    % 4 - wait margin end exit
    %======================================================================

    properties
        stf
        cfo % carrier frequency offset
        sto % start time offset
        enl % everage noise level
        gc  % gain control
        stage
        detected
        buf
        debug
        snr
    end

    methods
        function obj = STF_Handler(stf, options)
            arguments
                stf
                options.debug = false
            end
            obj.stf = stf;
            obj.cfo = 0.0;
            obj.sto = 0;
            obj.enl = 0.0;
            obj.gc  = 1.0;
            obj.stage = 0;
            obj.detected = 0;
            obj.buf = [];
            obj.snr = 0;
            obj.debug = options.debug;
        end

        function detected = detect(obj, waveform)
            
            rel_len = int32(floor(length(waveform)/obj.stf.symb_len-obj.stf.Nsymb)); % without cycle buffer
            if obj.debug 
                fprintf("Start detection, len = %d OFMD symbols\n", rel_len); 
            end

            det_mask_weight = sum(obj.stf.det_mask);

            for i = 1:rel_len
                det_buf = waveform((i-1)*obj.stf.symb_len+1:i*obj.stf.symb_len);
                OFDM_buf = det_buf(obj.stf.L+1:end);
                OFDM_buf = fft(OFDM_buf);
                
                pilot_power = OFDM_buf.*obj.stf.det_mask;

                pilot_power = sum(abs(pilot_power.^2));
                noise_power = sum(abs(OFDM_buf.^2))-pilot_power;

                pilot_power = pilot_power/det_mask_weight;
                noise_power = noise_power/(obj.stf.N-det_mask_weight);

                SNR = 10*log10(pilot_power/noise_power);
                obj.snr = SNR;
                
                if obj.debug 
                    fprintf("Symb:%4d Stage %d SNR(dB) %3.3f \n", i, obj.stage, SNR); 
                end

                if SNR < obj.stf.det_threshold %&& obj.stage ~= 4
                    obj.detected = 0;
                    obj.stage = 0;
                    continue;
                end

                if obj.stage == 0
                    obj.stage = 1;

                elseif obj.stage == 1
                    obj.stage = 2;
                    obj.detected = 0;

                elseif obj.stage == 2
                    obj.detected = obj.detected + 1;
                    if obj.detected >= obj.stf.margin1
                        obj.detected = 0;
                        obj.buf = [];
                        obj.stage = 3;
                    end
                
                elseif obj.stage == 3
                    obj.detected = obj.detected + 1;
                    obj.buf = cat(1, obj.buf, det_buf);

                    if obj.detected == obj.stf.est_symb

                        if obj.debug
                            fprintf("Start CFO est\n");
                        end

                        obj.buf = obj.buf(1:end-mod(length(obj.buf), obj.stf.period));
                        obj.buf = reshape(obj.buf, obj.stf.period, []);
                        
                        obj.buf = fft(obj.buf);
    
                        Ppos = int32(double(obj.stf.Ppos-1).*double(obj.stf.period)./double(obj.stf.N))+1;
                        
                        pilots = obj.buf(Ppos, :);
                        pilot_phases = unwrap(angle(pilots), [], 2);

                        x = repmat([1:length(pilot_phases)], length(Ppos), 1);
                        
                        obj.cfo = polyfit(x, pilot_phases, 1);
                        obj.cfo = obj.cfo(1)/2/pi/double(obj.stf.period);
                        
                        if obj.debug
                            fprintf("Pilot position: %d\n", Ppos);
                            fprintf("Rel CFO: %e\n", obj.cfo);
                            figure(100);
                            clf;
                            plot(pilot_phases.');
                            title('STF Pilot diff phases');
                            xlabel("smaple");
                            ylabel("phase");
                            grid("on");
                        end
                        obj.detected = 0;
                        obj.buf = [];
                        obj.stage = 4;
                    end

                elseif obj.stage == 4
                    obj.detected = obj.detected + 1;
                    if obj.detected >= obj.stf.margin2
                        obj.detected = 0;
                        obj.sto = (i-1)*obj.stf.symb_len+1+int32(obj.stf.symb_len/2);
                        obj.buf = [];

                        if obj.debug
                            fprintf("STO: %d\n", obj.sto);
                        end
                        
                        break;
                    end
                end
            end
            
            if obj.stage == 4
                obj.stage = 0;
                detected = 1;
            else
                detected = 0;
            end
        end
        
    end
end