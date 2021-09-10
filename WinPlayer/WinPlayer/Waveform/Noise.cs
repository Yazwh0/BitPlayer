using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Models;

namespace WinPlayer.Waveform
{
    class Noise : IVeraWaveform
    {
        public double Frequency { get; set; }
        private int _noteNumber;
        public int NoteNumber { 
            get => _noteNumber; 
            set {
                _noteNumber = value;
                Frequency = FrequencyLookup.Lookup(NoteNumber).Frequency;
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

        private int _value = 0;
        private Random _rnd = new Random();

        public WaveType WaveType => WaveType.Sawtooth;

        public Noise(double sampleRate)
        {
            _sampleRate = sampleRate;
        }

        public float GetNext()
        {
            cycle++;

            if (cycle > CycleWidth)
            {
                _value = (int)(_rnd.NextDouble() * 64);
                _value -= 32;
                cycle = 0;
            }

            var toReturn = _value * VolumeLookup.Lookup(_volume);

            return toReturn / 2048.0f;
        }
    }
}
