import numpy as np
import matplotlib.pyplot as plt
import adi
import os
import sys


class STF:
    
    def __init__(
            self,
            N,
            L,
            Nest_symb,
            margin1,
            margin2,
            mask_width,
            threshold,
            Ppos,
            threshold_symb = 1
        ):
        
        self.N = int(N)
        self.L = int(L)
        self.Nest_symb = int(Nest_symb)
        self.margin1 = int(margin1)
        self.margin2 = int(margin2)
        self.Nsymb = 1+1+self.margin1+self.Nest_symb+self.margin2
        self.symb_len = self.N+self.L
        self.mask_width = int(mask_width)
        self.threshold = threshold
        self.threshold_symb = threshold_symb

        self.Ppos = np.int32(np.round(Ppos))-1
        self.ampl = self.N/(self.Ppos.size)**0.5

        self.waveform = np.zeros([self.Nsymb, self.N], dtype=np.complex64)

        for i in range(self.Nsymb):
            self.waveform[i, self.Ppos] = self.ampl*np.exp(2j*np.pi*i*self.L/self.N*self.Ppos)

        self.waveform = np.fft.ifft(self.waveform, self.N, axis=1)
        self.waveform = np.hstack([self.waveform[:, -self.L:], self.waveform]).reshape(-1)

        self.det_mask = np.zeros(self.N)
        self.det_mask[self.Ppos] = 1
        self.det_mask = np.convolve(self.det_mask, np.ones(self.mask_width), "same")
        
        g = np.gcd.reduce(self.Ppos)

        self.T = N//g


class Handler:

    def __init__(
            self,
            stf:STF
    ):
        self.stf = stf
        self.cfo = 0.0
        self.sto = 0
        self.enl = 0.0
        self.gc  = 1.0
        self.stage = 0
        self.detected = 0
        self.buf = []
        self.snr = 0
        self.norm_snr = 0

    def detect(self, waveform):
        waveform = np.reshape(waveform, -1)
        rel_len = int(np.floor((waveform.size/self.stf.symb_len-self.stf.Nsymb)))
        det_mask_weight = np.sum(self.stf.det_mask)

        for i in range(rel_len):
            det_buf = waveform[i*self.stf.symb_len:(i+1)*self.stf.symb_len]
            OFDM_buf = np.fft.fft(det_buf[self.stf.L:])

            pilot_power = np.sum(np.abs(OFDM_buf*self.stf.det_mask)**2)
            noise_power = np.sum(np.abs(OFDM_buf)**2)-pilot_power

            pilot_power /= det_mask_weight
            noise_power /= self.stf.N - det_mask_weight

            self.norm_snr = 10*np.log10(pilot_power/noise_power)



            if self.norm_snr < self.stf.threshold and self.detected<self.stf.threshold_symb:
                self.detected = 0
                self.stage = 0
                continue

           
            if self.stage == 0:
                self.stage += 1

            elif self.stage == 1:
                
                self.stage += 1
                self.detected = 0

            elif self.stage == 2:
                self.detected += 1
                if self.detected == self.stf.margin1:
                    self.detected = 0
                    self.buf = np.zeros([self.stf.Nest_symb,self.stf.symb_len], dtype=np.complex64)
                   
                    self.stage = 3
            
            elif self.stage == 3:
                self.buf[self.detected, :] = np.copy(det_buf)
                self.detected += 1

                if self.detected == self.stf.Nest_symb:
                    self.buf = self.buf.reshape(-1)

                    cfo_buf = self.buf[:int(self.buf.size-(self.buf.size%self.stf.T))].reshape([int(self.stf.T), -1], order='F')
                    cfo_buf = np.fft.fft(cfo_buf, axis=0)

                    Ppos = np.array(self.stf.Ppos*self.stf.T/self.stf.N, dtype=np.int32)
                    pilots = cfo_buf[Ppos, :]
                    pilot_phases = np.unwrap(np.angle(pilots), axis=1)
                    pilot_phases = np.mean(pilot_phases, axis=0)

                    self.cfo = np.polyfit(np.arange(pilot_phases.size), pilot_phases, 1)[0]/2/np.pi/self.stf.T

                    phase = 0
                    self.buf = self.buf[:self.buf.size-(self.buf.size%self.stf.N)]
                    for k in range(self.buf.size):
                        self.buf[k] *= np.exp(-2j*np.pi*phase)
                        phase += self.cfo

                    self.buf = self.buf.reshape([self.stf.N, -1], order='F')
                    self.buf = np.abs(np.fft.fft(self.buf, axis=0))**2

                    pilot_power = np.sum(self.buf[self.stf.Ppos, :])
                    noise_power = np.sum(self.buf)-pilot_power

                    self.snr = 10*np.log10(pilot_power/noise_power)

                    self.detected = 0
                    self.buf = np.zeros([self.stf.Nest_symb,self.stf.symb_len], dtype=np.complex64)
                    self.stage = 4

            elif self.stage == 4:
                self.detected += 1
                if self.detected >= self.stf.margin2:
                    self.detected = 0
                    self.sto = (i+1)*self.stf.symb_len+self.stf.symb_len//2+1
                    break
        
        if self.stage == 4:
            self.stage = 0
            return 1
        
        else:
            return 0

        
if __name__ == "__main__":
    if len(sys.argv) < 8:
        raise ValueError("bad input arguments") 
    N           = int(sys.argv[1])
    L           = int(sys.argv[2])
    Nest_symb   = int(sys.argv[3])
    margin1     = int(sys.argv[4])
    margin2     = int(sys.argv[5])
    mask_width  = int(sys.argv[6])
    threshold   = float(sys.argv[7])


