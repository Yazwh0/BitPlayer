using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Models;
using WinPlayer.Waveform;

namespace WinPlayer.Waveform
{
    public class Triangle : IVeraWaveform
    {
        public double Frequency { get; set; }
        private int _noteNumber;
        public int NoteNumber
        {
            get => _noteNumber;
            set
            {
                _noteNumber = value;
                Frequency = FrequencyLookup.Lookup(NoteNumber).Frequency;
            }
        }

        private int _volume = 63;
        public int Volume
        {
            get => _volume;
            set
            {
                if (_volume == 0 && value != 0)
                    Phase = 0;

                _volume = Math.Min(value, 63);
            }
        }

        public int Width { get; set; }

        private readonly double _sampleRate;
        public WaveType WaveType => WaveType.Triangle;

        public Triangle(double sampleRate)
        {
            _sampleRate = sampleRate;
        }

        private const double OneCycle = 10000.0;
        private const double HalfCycle= 5000.0;
        
        private double Phase = 0.0;

        public float GetNext()
        {
            if (_volume == 0 || Frequency == 0)
                return 0;

            var toPlay = Phase > HalfCycle ?
                (OneCycle - Phase) / HalfCycle :
                Phase / HalfCycle;

            toPlay *= 64;
            toPlay -= 32;
            toPlay *= VolumeLookup.Lookup(_volume);

            var cwidth = 1.0 / Frequency * _sampleRate;    // steps per cycle
            var scale = OneCycle / cwidth;                  // cycle scaled;

            Phase += scale; 
            Phase = Phase % OneCycle;

            return (int)toPlay / 2048.0f;
        }
    }
}
