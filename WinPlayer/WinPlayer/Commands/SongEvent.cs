using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using WinPlayer.Waveform;

namespace WinPlayer.Command
{
    public class SongEvent : ICommand
    {
        public Models.Note? Note { get; set; }
        public short Parameters { get; set; }
        public void ApplyNext(IVeraWaveform generator)
        { }
    }
}
