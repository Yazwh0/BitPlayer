using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Command;
using WinPlayer.Models;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class FrequencySlideUp : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }

        private int _step = 0;
        private int _current = 0;
        private int _count = 0;
        private bool _initalised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                _step = ((ICommand)this).Parameters0;
                _count = ((ICommand)this).Parameters1;
                _current = 0;
            }

            if (_count != 0)
            {
                _current += _step;
                _count--;
            }

            generator.Frequency += _current * _step;
        }
    }

    public class FrequencySlideDown : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }

        private int _step = 0;
        private int _current = 0;
        private int _count = 0;
        private bool _initalised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                _step = ((ICommand)this).Parameters0;
                _count = ((ICommand)this).Parameters1;
                _current = 0;
            }

            if (_count != 0)
            {
                _current += _step;
                _count--;
            }

            generator.Frequency -= _current * _step;
        }
    }
}
