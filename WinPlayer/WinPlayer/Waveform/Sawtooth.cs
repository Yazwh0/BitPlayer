using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Models;
using WinPlayer.Waveform;

namespace WinPlayer.Waveform
{
    class Sawtooth : IVeraWaveform
    {
        public double Frequency { get; set; }
        private int _noteNumber { get; set; }
        public int NoteNumber
        {
            get => _noteNumber;
            set
            {
                _noteNumber = value;
                Frequency = FrequencyLookup.Lookup(NoteNumber).Frequency;
                if (_noteNumber == 0)
                {
                    cycle = CycleWidth / 2;
                }
            }
        }

        private int _volume = 63;
        public int Volume
        {
            get => _volume;
            set => _volume = Math.Min(value, 63);
        }

        public int Width { get; set; }

        private readonly double _sampleRate;
        private int cycle = 0;
        private int CycleWidth => (int)(1.0 / Frequency * _sampleRate);

        public WaveType WaveType => WaveType.Sawtooth;

        public Sawtooth(double sampleRate)
        {
            _sampleRate = sampleRate;
        }

        public float GetNext()
        {
            cycle++;

            int toPlay = (int)((cycle / (float)CycleWidth) * 64);

            toPlay -= 32;
            toPlay *= VolumeLookup.Lookup(_volume);

            if (cycle > CycleWidth)
            {
                cycle = 0;
            }

            return toPlay / 2048.0f;
        }
    }
}
