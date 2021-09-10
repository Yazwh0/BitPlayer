using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class Warble : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set ; }

        private int _state = 0;
        private double _baseFreq = 0;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (_state > 3)
                _state = 0;

            switch (_state)
            {
                case 0:
                    if (_baseFreq == 0)
                        _baseFreq = generator.Frequency;
                    else
                        generator.Frequency = _baseFreq;
                    break;
                case 1:
                    generator.Frequency = _baseFreq + Parameters;
                    break;
                case 2:
                    generator.Frequency = _baseFreq ;
                    break;
                case 3:
                    generator.Frequency = _baseFreq - Parameters;
                    break;
            }

            _state++;
        }

        public void Remove(IVeraWaveform generator)
        {
            generator.Frequency = _baseFreq;
        }
    }
}
