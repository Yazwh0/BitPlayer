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
    public class NoteSlide : ICommand
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
                var param1 = ((ICommand)this).Parameters0;
                _step = param1 > 127 ? param1 - 256 : param1;
                _count = ((ICommand)this).Parameters1;
                _current = 0;
            }

            if (_count != 0)
            {
                _current += _step;
                _count--;
            }

            generator.NoteNumber = generator.NoteNumber + _current;

            //Debug.WriteLine($"{generator.NoteNumber}");
        }
    }
}
