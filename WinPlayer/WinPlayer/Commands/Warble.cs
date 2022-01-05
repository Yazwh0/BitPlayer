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
        private int _stateStep = 0;
        private double _baseFreq = 0;
        private int _stateStepStart = 0;

        private bool _initialised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initialised)
            {
                _stateStepStart = ((ICommand)this).Parameters0;
                _stateStep = _stateStepStart;
                _state = 0;
                _baseFreq = generator.Frequency;
            }

            switch (_state)
            {
                case 0:
                    generator.Frequency = FrequencyLookup.FrequencyStep(generator.NoteNumber, 0);
                    break;
                case 1:
                    generator.Frequency = FrequencyLookup.FrequencyStep(generator.NoteNumber, 1);
                    break;
                case 2:
                    generator.Frequency = FrequencyLookup.FrequencyStep(generator.NoteNumber, 0);
                    break;
                case 3:
                    generator.Frequency = FrequencyLookup.FrequencyStep(generator.NoteNumber-1, 3);
                    break;
            }

            _stateStep--;
            if (_stateStep == 0)
            {
                _state++;
                _stateStep = _stateStepStart;

                if (_state > 3)
                    _state = 0;
            }
        }

        public void Remove(IVeraWaveform generator)
        {
            generator.Frequency = _baseFreq;
        }
    }
}
