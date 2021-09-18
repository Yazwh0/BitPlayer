using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class FrequencySlide : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }

        private int _steps = 0;
        private int _step = 0;
        private int _current = 0;

        private bool _initalised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                var param1 = ((ICommand)this).Parameters0;
                _step = param1 > 127 ? param1 - 256 : param1;
                _steps = ((ICommand)this).Parameters1;
                _current = 0;
            }
            else
            {
                if (_current < _steps || _steps == 0)
                    _current += _step;

                generator.Frequency = FrequencyLookup.Lookup(generator.NoteNumber).Frequency + FrequencyLookup.FrequencySlide(_step > 1 ? generator.NoteNumber : generator.NoteNumber - 1) * _current;
                Debug.WriteLine($"{generator.Frequency} - {_current}");
            }
        }
    }
}
