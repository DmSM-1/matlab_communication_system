import numpy as np
import adi
import STF
import time


class SDR:
    def __init__(
            self, 
            uri='ip:192.168.4.1', 
            fc=2_800_000_000, 
            fs=5_000_000, 
            rf_bandwidth = 20_000_000, 
            buffer_size = 2**16,
            rx_hardwaregain_chan0 = 60,
            tx_hardwaregain_chan0 = -10,
            stf = False,
            tx_cycle_buffer = False
        ):
        """Инициализация подключения к PLUTO"""

        self.uri = uri
        self.fc = int(fc)
        self.fs = int(fs)
        self.rf_bandwidth = int(rf_bandwidth)
        self.buffer_size = int(buffer_size)
        self.rx_hardwaregain_chan0 = int(rx_hardwaregain_chan0)
        self.tx_hardwaregain_chan0 = int(tx_hardwaregain_chan0)
        self.stf = stf
        self.tx_cycle_buffer = tx_cycle_buffer

        self.sdr = adi.Pluto(self.uri)    

        self.sdr.rx_lo = self.fc
        self.sdr.tx_lo = self.fc

        self.sdr.sample_rate = self.fs

        self.sdr.rx_rf_bandwidth = self.rf_bandwidth
        self.sdr.tx_rf_bandwidth = self.rf_bandwidth

        self.sdr.rx_buffer_size = self.buffer_size
        self.sdr.tx_buffer_size = self.buffer_size

        self.sdr.gain_control_mode_chan0 = "manual"
        self.sdr.gain_control_mode_chan1 = "manual"
        self.sdr.rx_hardwaregain_chan0 = self.rx_hardwaregain_chan0
        self.sdr.tx_hardwaregain_chan0 = self.tx_hardwaregain_chan0

        self.sdr.tx_cyclic_buffer = self.tx_cycle_buffer

        self.stf_h = False
        self.detect = False

        if stf:
            self.stf_h = STF.Handler(self.stf)

        self.recv()


    def send(self, data):
        """Отправить I/Q данные"""
        # import matplotlib.pyplot as plt
        # # plt.plot(np.abs(np.fft.fftshift(np.fft.fft(data))))
        # # plt.show()
        # plt.plot(np.real(data))
        # plt.plot(np.imag(data))
        # plt.show()
        self.sdr.tx(data)

        return True
    

    def recv(self):
        """Получить I/Q данные"""
        
        received = self.sdr.rx()

        return received
    

    def recv_det(self, tx_len):
        """Получить I/Q данные"""

        a = time.time()
        tx_len = int(tx_len)
        guard_space = self.stf_h.stf.waveform.size+self.stf_h.stf.symb_len

        self.recv()
        self.recv()
        self.recv()
        
        frame_buf = np.zeros(tx_len+2*guard_space, dtype=np.complex64)
        received = np.zeros(2*self.sdr.rx_buffer_size, dtype=np.complex64)
        received[self.sdr.rx_buffer_size:] = self.sdr.rx()
        
        for i in range(10):
            received[:self.sdr.rx_buffer_size] = received[self.sdr.rx_buffer_size:]
            received[self.sdr.rx_buffer_size:] = self.sdr.rx()

            self.detect = self.stf_h.detect(received[:self.sdr.rx_buffer_size+2*self.stf.waveform.size])
            if self.detect: 
                self.stf_h.sto = max(0, self.stf_h.sto-guard_space)

                red = 0
                data_ptr = self.stf_h.sto
                while red < frame_buf.size:
                    ready_to_read = min(frame_buf.size-red, received.size-data_ptr)
                    frame_buf[red:red+ready_to_read] = received[data_ptr:data_ptr+ready_to_read]
                    red      += ready_to_read
                    data_ptr += ready_to_read 
                    if data_ptr == received.size:
                        data_ptr = self.sdr.rx_buffer_size
                        received[self.sdr.rx_buffer_size:] = self.sdr.rx()
                
                return frame_buf
        
        return received


    # def recv_det(self):
        
    #     received = self.sdr.rx()

    #     detect = self.stf_h.detect(received)
    #     if not detect: 
    #         return [received, 0]
        
    #     stf_len = self.stf_h.stf.waveform.size
    #     self.stf_h.sto = max(0, self.stf_h.sto-2*stf_len)
    #     received = received[self.stf_h.sto:min(received.size, self.stf_h.sto+self.tx_len+2*stf_len)]

    #     return [received, 1]

    
    def close(self):
        """Закрыть подключение"""

        try:
            self.sdr.rx_destroy_buffer()
            self.sdr.tx_destroy_buffer()
            del self.sdr
        except:
            pass
