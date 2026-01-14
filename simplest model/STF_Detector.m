classdef STF_Detector < handle

    % State machine =======================================================
    % 0 - detect stf
    % 1 - est gain   
    % 2 - wait margin
    % 3 - cfo estimate
    % 4 - enl estimate
    % 5 - wait margin end exit
    %======================================================================

    properties
        stf
        cfo % carrier frequency offset
        enl % everage noise level
        gc  % gain control
        stage
        detected
        debug
    end

    methods
        function obj = STF_Detector(stf, options)
            arguments
                stf
                options.debug = false
            end
            obj.stf = stf;
            obj.cfo = 0.0;
            obj.enl = 0.0;
            obj.gc  = 1.0;
            obj.stage = 0;
            obj.detected = 0;
            obj.debug = options.debug;
        end

        function detected = detect(obj, waveform)
            
            rel_len = int32(floor(length(waveform)/obj.stf.symb_len-obj.stf.Nsymb)); % without cycle buffer
            if obj.debug 
                fprintf("Start detection, len = %d OFMD symbols\n", rel_len); 
            end

            det_mask_weight = sum(obj.stf.det_mask);

            for i = 1:rel_len %Attention
                det_buf = waveform((i-1)*obj.stf.symb_len+1:i*obj.stf.symb_len);
                det_buf = det_buf(obj.stf.L+1:end);
                det_buf = fft(det_buf);
                
                pilot_power = det_buf.*obj.stf.det_mask;

                pilot_power = sum(abs(pilot_power.^2));
                noise_power = sum(abs(det_buf.^2))-pilot_power;

                pilot_power = pilot_power/det_mask_weight;
                noise_power = noise_power/(obj.stf.N-det_mask_weight);

                SNR = pilot_power/noise_power;
                
                if obj.debug 
                    fprintf("Symb:%4d Stage %d SNR(dB) %3.3f \n", i, obj.stage, db(SNR)); 
                end

                if SNR < obj.stf.det_threshold
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
                        obj.stage = 3;
                    end

                end
            end

            detected = 0;
        end
        
    end
end