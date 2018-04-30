# coding: utf-8
import serial
import struct
import array

class LogiAna:

    DIVIDE_SETTING_CMD = 1
    POS_SETTING_CMD = 2
    TRIGGER_SETTING_CMD = 3
    CONTROL_CMD = 4
    READ_DATA_CMD = 5

    SAMPLE_COUNT = 128 * 1024

    def __init__(self, serial_port):
        self.serial = serial.Serial(serial_port, 115200)
        self.serial.flushOutput()
        self.serial.flushInput()

    def write_cmd(self, cmd, val):
        self.serial.write([0x80 | cmd, val])
        self.serial.flush()

    def read_cmd(self, cmd):
        self.serial.flushInput()
        self.serial.write([cmd])
        self.serial.flush()
        s = self.serial.read()
        return struct.unpack('B', s)[0]

    def read_data(self):
        self.serial.flushInput()
        self.serial.write([LogiAna.READ_DATA_CMD])
        self.serial.flush()
        s = self.serial.read(LogiAna.SAMPLE_COUNT)
        a = array.array('B')
        a.fromstring(s)
        return a

    def set_divide(self, val):
        self.write_cmd(LogiAna.DIVIDE_SETTING_CMD, val)

    def get_divide(self):
        return self.read_cmd(LogiAna.DIVIDE_SETTING_CMD)

    def set_pos(self, val):
        self.write_cmd(LogiAna.POS_SETTING_CMD, val)

    def get_pos(self):
        return self.read_cmd(LogiAna.POS_SETTING_CMD)

    def set_trigger(self, rising_edge_trigger, trigger_ch):
        val = 0
        if rising_edge_trigger:
            val |= 0x80
        val |= trigger_ch
        self.write_cmd(LogiAna.TRIGGER_SETTING_CMD, val)

    def get_trigger(self):
        val = self.read_cmd(LogiAna.TRIGGER_SETTING_CMD)
        if val & 0x80:
            rising_edge_trigger = True
        else:
            rising_edge_trigger = False
        trigger_ch = val & 0x07
        return (rising_edge_trigger, trigger_ch)

    def is_running(self):
        val = self.read_cmd(LogiAna.CONTROL_CMD)
        if val & 0x01:
            return True
        else:
            return False

    def start(self):
        self.write_cmd(LogiAna.CONTROL_CMD, 0x01)

    def save_vcd(self, fname):
        samples = self.read_data()
        steps_per_sample = self.get_divide() + 1
        with open(fname, "w") as f:
            f.write("$timescale 10 ns $end\n"
                    "$scope module capdata $end\n"
                    "$var wire 1 a CH0 $end\n"
                    "$var wire 1 b CH1 $end\n"
                    "$var wire 1 c CH2 $end\n"
                    "$var wire 1 d CH3 $end\n"
                    "$var wire 1 e CH4 $end\n"
                    "$var wire 1 f CH5 $end\n"
                    "$var wire 1 g CH6 $end\n"
                    "$var wire 1 h CH7 $end\n"
                    "$upscope $end\n"
                    "$enddefinitions $end\n")
            def write_ch_val(val, ch):
                bit = (val >> ch) & 0x01
                ch_id = chr(ord('a') + ch)
                f.write('{0}{1}\n'.format(bit, ch_id))
            # 最初の値
            f.write("$dumpvars\n")
            val = samples.pop(0)
            for ch in range(8):
                write_ch_val(val, ch)
            f.write("$end\n")
            # 残りの値
            prev_val = val
            for (index, val) in enumerate(samples):
                if prev_val == val:
                    continue
                f.write('#{0}\n'.format((index + 1) * steps_per_sample))
                changed_ch_bitmap = prev_val ^ val
                for ch in range(8):
                    if changed_ch_bitmap & (1 << ch):
                        write_ch_val(val, ch)
                prev_val = val
            # 最後の〆
            f.write('#{0}\n'.format(LogiAna.SAMPLE_COUNT * steps_per_sample))
