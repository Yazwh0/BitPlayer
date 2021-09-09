using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace WinPlayer.Models
{
    public class Track
    {
        public int TrackLength { get; set; } = 64;

        public Note[] Notes { get; set; }

        public Track()
        {
            Notes = new Note[TrackLength];
            for (var i = 0; i < TrackLength; i++)
            {
                Notes[i] = new Note() { Position = i };
            }
        }
    }
}
