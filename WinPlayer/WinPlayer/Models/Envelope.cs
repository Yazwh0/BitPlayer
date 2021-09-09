using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer.Models
{
    public class Envelope
    {
        public int TimeLength { get; set; }
        public int Volume { get; set; }
        public int Width { get; set; }

        public (int Time, int Volume, int Width) Deconstruct() => (TimeLength, Volume, Width);
    }
}
