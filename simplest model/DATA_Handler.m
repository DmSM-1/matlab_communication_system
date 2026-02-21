classdef DATA_Handler < handle
    properties
        N
        L
        Ndat
        Npil
        Mod_pow
        Nsymb
        Cod_rate
        NumGuardBandCarriers
        left_guard
        right_guard
        pilotIdx
        pilAmpl
        payload
        payload_per_symbol
        ofdm
        ofdmMod
        ofdmDemod
        data
        mod_data
        waveform
        ang
        
        eqv
        noise
        debug
        eqv_pilotIdx
        dataIdx
        activeIdx
        alpha
        beta
        crcCfg
        trellis
        encoder
        decoder

        interleaver
        window
        soft
        std_eqv_err
        est_method
        Rh
    end
    methods
        function obj = DATA_Handler(options)
            arguments
                options.N = 64;
                options.L = 16;
                options.Ndat = 48;
                options.Npil = 2;
                options.pilAmpl = 5.0;
                options.Bw = 0.5;
                options.Mod_pow = 1;
                options.Nsymb = 1;
                options.Cod_rate = 1;
                options.alpha = 1.0;
                options.beta = 0.1;
                options.guards = [];
                options.DC_guard = 1;
                options.win_slope = 0;
                options.soft = 1;
                options.debug = false;
                options.est_meth = "simple";
            end
            obj.N = options.N;
            obj.L = options.L;
            obj.Npil = options.Npil;
            obj.pilAmpl = options.pilAmpl;
            obj.Nsymb = options.Nsymb;
            obj.soft = options.soft;
            obj.trellis = poly2trellis(7, [171, 133], 171);
            obj.est_method = options.est_meth;
            
            obj.ofdm = OFDM( ...
                N=obj.N, ...
                L=obj.L, ...
                Npil=obj.Npil, ...
                Bw=options.Bw, ...
                guards=options.guards, ...
                DC_guards=options.DC_guard ...
            );
            obj.Ndat = obj.ofdm.Ndat;
            obj.Mod_pow = options.Mod_pow;
            obj.Cod_rate = options.Cod_rate;
            obj.payload_per_symbol = floor(obj.Ndat*obj.Cod_rate*obj.Mod_pow)-32-6*(obj.Cod_rate~=1);
            obj.payload_per_symbol = obj.payload_per_symbol - mod(obj.payload_per_symbol, obj.Mod_pow);
            obj.payload = obj.Nsymb*obj.payload_per_symbol;
            obj.data = [];
            obj.mod_data = [];
            obj.waveform = [];
            obj.noise = [];
            obj.ang = zeros(obj.Nsymb, 1);
            obj.std_eqv_err = zeros(obj.Nsymb, 1);
            obj.eqv = complex(ones(obj.N, 1));
            obj.debug = options.debug;
            obj.eqv_pilotIdx = obj.ofdm.pilots-obj.ofdm.left_guard+1;
            obj.dataIdx = obj.ofdm.data-obj.ofdm.left_guard+1;
            obj.activeIdx = obj.ofdm.active-obj.ofdm.left_guard+1;
            obj.alpha = options.alpha;
            obj.beta = options.beta;
            obj.Rh = (1/obj.L)*eye(obj.L);
            poly = 'z^32 + z^26 + z^23 + z^22 + z^16 + z^12 + z^11 + z^10 + z^8 + z^7 + z^5 + z^4 + z^2 + z + 1';
            obj.crcCfg = crcConfig(Polynomial=poly,ChecksumsPerFrame=1);

            obj.encoder = comm.ConvolutionalEncoder( ...
                'TrellisStructure', obj.trellis, ...
                'TerminationMethod', 'Terminated');

            if obj.soft
                obj.decoder = comm.ViterbiDecoder( ...
                    'TrellisStructure', obj.trellis, ...
                    'TerminationMethod', 'Terminated', ...
                    'InputFormat', 'Unquantized', ...
                    'TracebackDepth', 35);
            else
                obj.decoder = comm.ViterbiDecoder( ...
                    'TrellisStructure', obj.trellis, ...
                    'TerminationMethod', 'Terminated', ...
                    'InputFormat', 'Hard', ...     
                    'TracebackDepth', 35);
            end

            if options.win_slope
                obj.window = tukeywin(obj.L+obj.N, 2*options.win_slope/(obj.L+obj.N));
            end
        end
        function data = generate_data(obj, options)
            arguments
                obj 
                options.source_data = [] 
                options.Nsymb = obj.Nsymb
            end
            
            if isempty(options.source_data)
                options.source_data = randi([0, 1], obj.payload_per_symbol, options.Nsymb);
            else
                options.source_data = reshape(options.source_data, obj.payload_per_symbol, options.Nsymb);
            end
            msg = crcGenerate(options.source_data, obj.crcCfg);
            
            source_bits = zeros(obj.Ndat*obj.Mod_pow, options.Nsymb);
            if obj.Cod_rate~=1
                % msg = vertcat(msg, zeros(6, options.Nsymb));
                for i = 1:options.Nsymb
                    % source_bits(1:2*(obj.payload_per_symbol+32+6),i) = convenc(msg(:,i), obj.trellis);
                    source_bits(1:2*(obj.payload_per_symbol+32+6),i) = obj.encoder(msg(:,i));
                end
            else
                for i = 1:options.Nsymb
                    source_bits(1:obj.payload_per_symbol+32,i) = msg(:,i);
                end
            end
            data = source_bits(:);
        end
        function waveform = get_waveform(obj, data)
            obj.data = reshape(data, [], 1);
            pilots = pskmod(zeros(obj.Npil, obj.Nsymb), 2).*obj.pilAmpl;
            obj.mod_data = qammod(obj.data, 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
            obj.mod_data = reshape(obj.mod_data, obj.Ndat, []);
            obj.waveform = complex(zeros(obj.N+obj.L, obj.Nsymb));
            for i = 1:obj.Nsymb
                obj.waveform(:, i) = obj.ofdm.mod(obj.mod_data(:, i), pilots(:, i));
            end
            obj.waveform = obj.waveform(:);
            obj.waveform = obj.waveform*obj.N/sqrt(length(obj.activeIdx));
            waveform = obj.waveform;
        end
        function eqv = set_eqv(obj, ltf_handler)
            obj.eqv = ltf_handler.eqv;
            obj.eqv = fftshift(obj.eqv);
            obj.eqv = obj.eqv(obj.ofdm.left_guard:obj.ofdm.right_guard);
            eqv = obj.eqv;

            obj.noise = ltf_handler.noise;
            obj.noise = fftshift(obj.noise);
            obj.noise = obj.noise(obj.ofdm.left_guard:obj.ofdm.right_guard);
            obj.noise = obj.noise.*sqrt(obj.ofdm.Bw);

        end
        function [cfo, sfo] = get_freq(obj, waveform)
            mod_data = complex(zeros(obj.ofdm.bandsize, obj.Nsymb));
            pilots = complex(zeros(obj.Npil, obj.Nsymb));
            iter = 0;
            
            for i = 1:obj.Nsymb
                [mod_data(:, i), ~, pilots(:, i)] = obj.ofdm.demod(waveform(iter+1:iter+(obj.N+obj.L)));
                iter = iter+(obj.N+obj.L);
            end
            pilots = unwrap(angle(pilots.'));
            
            sfo = median(diff(pilots(:,obj.Npil)-pilots(:,1)));
            sfo = sfo/(obj.ofdm.pilots(obj.Npil)-obj.ofdm.pilots(1));
            
            pilots = mean(pilots, 2);
            x = double(1:obj.Nsymb);
            p = polyfit(x, pilots, 1);
            cfo = p(1)/(obj.L+obj.N);
        end
        function [eqv_data, eqv_pilots, mod_data, coded_data, decoded_data] = get_data(obj, waveform, options)
            arguments
                obj 
                waveform 
                options.crc = false 
                options.ideal = false
                options.source = []
                options.snr = 10;
            end
            mod_data = complex(zeros(obj.ofdm.bandsize, obj.Nsymb));
            ifft_data = complex(zeros(obj.ofdm.bandsize, obj.Nsymb));
            pilots = complex(zeros(obj.Npil, obj.Nsymb));
            eqv_data = zeros(size(ifft_data));
            decoded_data = zeros(obj.payload_per_symbol, obj.Nsymb);
            indices = (1:obj.ofdm.bandsize).';
            if ~isempty(options.source)
                options.source = reshape(options.source, [], obj.Nsymb);
            end
            iter = 0;
            
            for i = 1:obj.Nsymb
                [mod_data(:, i), ~, pilots(:, i)] = obj.ofdm.demod(waveform(iter+1:iter+(obj.N+obj.L)));
                iter = iter+(obj.N+obj.L);
            end
            pilots = unwrap(angle(pilots.'));
            sfo = median(diff(pilots(:,obj.Npil)-pilots(:,1)));
            sfo = sfo/(obj.ofdm.pilots(obj.Npil)-obj.ofdm.pilots(1));
            pilots = mean(pilots, 2);
            obj.ang(:,1) = pilots;
            x = double(1:obj.Nsymb);
            p = polyfit(x, pilots, 1);
            dp = p(1)/(obj.L+obj.N);
            phase = 0;
            
            for i = 1:length(waveform)
                phase = phase + dp;
                waveform(i) = waveform(i)*exp(-1i*phase);
            end
            
            iter = 0;
            t = 1:length(obj.eqv);
            t = t.';
            t = t-length(obj.eqv)/2;
            
            
            for i = 1:obj.Nsymb
                [ifft_data(:, i), ~, ~] = obj.ofdm.demod(waveform(iter+1:iter+(obj.N+obj.L)));
                iter = iter+obj.N+obj.L;
                eqv_data(:, i) = ifft_data(:, i).*obj.eqv;
                
                pilot_eqv = eqv_data(obj.eqv_pilotIdx, i)./obj.pilAmpl;

                p = polyfit(obj.eqv_pilotIdx, unwrap(angle(pilot_eqv)), 1);
                pilot_eqv = exp(-1i*polyval(p , indices));

                eqv_data(:, i) = eqv_data(:, i).*pilot_eqv;
                
                eqv_pilots = eqv_data(obj.eqv_pilotIdx, i)./obj.pilAmpl;
                eqv_data(:, i) = eqv_data(:, i)./sqrt(mean(abs(eqv_pilots.^2)));
                coded_data = eqv_data(obj.dataIdx, i);
                
                if ~isempty(options.source)
                    pilots = pskmod(zeros(obj.Npil, 1), 2)*obj.pilAmpl;
                    rx_mod_res_data = qammod(options.source(:,i), 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
                
                    [rx_demod_res_data, ~, ~] = obj.ofdm.demod(obj.ofdm.mod(rx_mod_res_data, pilots));
                    new_H = ifft_data(:, i)./rx_demod_res_data;
                                 
                    new_eqv = conj(new_H)./(abs(new_H.^2)+1e-3);
                    obj.eqv = obj.eqv + obj.beta*(new_eqv-obj.eqv);
                    val = polyfit(obj.eqv_pilotIdx, angle(conj(obj.eqv(obj.eqv_pilotIdx))), 1);
                    obj.ang(i,1) = val(2);
                    continue
                end
                snr_per_sc = options.snr + 10*log10((obj.Ndat + obj.Npil) / obj.N);
                noise_var = 10^(-snr_per_sc / 10);
                llr = [];
                if obj.Cod_rate ~= 1
                    
                    buf = [];
                    err = 0;
                    if obj.soft
                        llr = qamdemod( ...
                            coded_data, 2^obj.Mod_pow, 'gray', ...
                            'OutputType', 'approxllr', ...
                            'UnitAveragePower', true, ...
                            'NoiseVariance', noise_var);
                        coded_data = reshape(llr, [], 1);
                        
                        buf = coded_data(1:2*(obj.payload_per_symbol+32+6),:);
                        buf = obj.decoder(buf);
                        coded_data = coded_data < 0;
                    else
                        coded_data = qamdemod(coded_data, 2^obj.Mod_pow, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true);
                        coded_data = reshape(coded_data, [], 1);
                        buf = coded_data(1:2*(obj.payload_per_symbol+32+6),:);
                        buf = obj.decoder(buf);
                    end

                    buf = buf(1:end-6, :);
                    [~,err] = crcDetect(buf,obj.crcCfg);

                    if ~err
                        decoded_data(:,i) = buf(1:end-32, :);
                    else
                        decoded_data(:,i) = coded_data(1:2:2*(obj.payload_per_symbol),:);
                    end
                    coded_data = obj.generate_data(source_data=decoded_data(:, i), Nsymb=1);
                else
                    coded_data = qamdemod(coded_data, 2^obj.Mod_pow, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true);
                    coded_data = reshape(coded_data, [], 1);
                    [~,err] = crcDetect(coded_data,obj.crcCfg);
                    decoded_data(:,i) = coded_data(1:obj.payload_per_symbol, :);
                end
                if ~(err&&options.crc)
                    pilots = pskmod(zeros(obj.Npil, 1), 2)*obj.pilAmpl;
                    rx_mod_res_data = qammod(coded_data, 2^obj.Mod_pow, 'gray', 'InputType', 'bit', 'UnitAveragePower', true);
                    
                    [rx_demod_res_data, ~, ~] = obj.ofdm.demod(obj.ofdm.mod(rx_mod_res_data, pilots));
    
                    Y = ifft_data(:, i) ./ obj.N .* sqrt(length(obj.activeIdx));
                    X = rx_demod_res_data;

                    dX  = eqv_data(:, i)-X;
                    obj.noise = sqrt((1-obj.beta)*obj.noise.^2 + obj.beta*abs(dX).^2);
                    new_H = Y./X;

                    if obj.est_method == "simple"
                        new_eqv = conj(new_H)./(abs(new_H).^2+1e-3);
                    else
                        sigma_z2 = mean(abs(dX).^2);
                        sigma_d2 = sigma_z2.*abs(obj.eqv).^2;
                        sigma_d2 = sigma_d2(obj.dataIdx);
                        
                        
                        dX  = abs(dX);
                        ndX = dX./abs(X);

                        constel = qammod(0:2^obj.Mod_pow-1, 2^obj.Mod_pow, 'gray', 'UnitAveragePower', true).';
                        dist2 = abs(eqv_data(obj.dataIdx, i) - constel.').^2;

                        Pd = 1./pi./sigma_d2.*exp(-dX(obj.dataIdx).^2./sigma_d2);
                        Pd_all = (1./(pi*sigma_d2)) .* exp(-dist2 ./ sigma_d2);
                        Pd_others = sum(Pd_all, 2) - Pd;

                        R = log(max(Pd./Pd_others, 1e-6));

                        % rel_indexes = sort([obj.dataIdx; obj.eqv_pilotIdx]);
                        % rel_indexes = intersect(obj.activeIdx,find(ndX<2^(-obj.Mod_pow/2+1)));
                        rel_indexes = sort([obj.dataIdx(find(R>-2)); obj.eqv_pilotIdx]);

                        Rz_inv = 1/sigma_z2*eye(length(rel_indexes));

                        Xrp = X(rel_indexes);
                        Yrp = Y(rel_indexes);
    
                        fft_indexes = mod((obj.ofdm.left_guard:obj.ofdm.right_guard)-obj.N/2, obj.N);
                        fft_indexes(fft_indexes==0) = obj.N; 
                        
                        F   = dftmtx(obj.N);
                        F   = F(fft_indexes, 1:obj.L);
                        Frp = F(rel_indexes, :);          


                        A = diag(X) * F;
                        h = (A'*A+1e-6*eye(obj.L)) \ (A' * Y);
                        Arp = diag(Xrp) * Frp;
                        h_rp = (Arp'*Arp+1e-6*eye(obj.L)) \ (Arp' * Yrp);
                        H_rp = F * h_rp; 
                        h_rp_lmmse = ((obj.Rh+1e-6*eye(obj.L))\eye(obj.L)+Arp'*Rz_inv*Arp)\(Arp'*Rz_inv*Yrp);
                        H_rp_lmmse = F * h_rp_lmmse;
                       
                        if obj.est_method == "LMMSE"
                            new_eqv = conj(H_rp_lmmse)./(abs(H_rp_lmmse).^2+1e-3);
                        else
                            new_eqv = conj(H_rp)./(abs(H_rp).^2+1e-3);
                        end

                        obj.Rh = (1-obj.alpha)*obj.Rh+obj.alpha*(h*h');
                    end

                    
                    obj.eqv = (1-obj.beta)*obj.eqv + obj.beta*new_eqv;
                    
                end

                obj.eqv = obj.eqv.*exp(-1i*sfo*t);
                obj.std_eqv_err(i) = std(abs(obj.eqv(obj.dataIdx))-1);
            end
            eqv_pilots      = eqv_data(obj.eqv_pilotIdx, :);
            eqv_data        = eqv_data(obj.dataIdx, :);
            coded_data      = reshape(qamdemod(eqv_data, 2^obj.Mod_pow, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true), [], 1);
            decoded_data    = reshape(decoded_data, [], 1);
        end
    end
end