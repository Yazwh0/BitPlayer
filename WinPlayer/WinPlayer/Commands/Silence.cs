using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Command;
using WinPlayer.Models;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class Silence : ICommand
    {
        public Note? Note { get; set; }
        public short Parameters { get; set; }

        private int _count = 0;
        private bool _initalised = false;

        public void ApplyNext(IVeraWaveform generator)
        {
            if (!_initalised)
            {
                _initalised = true;
                _count = ((ICommand)this).Parameters0;
            }

            if (_count == 0)
                generator.Volume = 0;
            else
                _count--;
        }
    }
}
