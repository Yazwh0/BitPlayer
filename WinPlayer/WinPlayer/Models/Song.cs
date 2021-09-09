using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer.Models
{
    public class Song
    {
        public string Name { get; set; } = "Song";
        public List<Instrument> Instruments { get; set; } = new List<Instrument>();
        public List<Pattern> Patterns { get; set; } = new List<Pattern>();
        public List<int> Playlist { get; set; } = new List<int>();
        public int Tracks { get; set; } = 16; 
    }
}
