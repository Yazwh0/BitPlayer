using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Navigation;
using System.Windows.Shapes;

namespace WinPlayer.Controls
{
    public class TrackControlTradeUpdateEventArgs : EventArgs
    {
    }

    public partial class TrackControl : UserControl
    {
        private Models.Track? _track;
        private int _instrumentNumber = 0;

        private Models.Track? _copiedTrack = null;

        public event EventHandler<TrackControlTradeUpdateEventArgs>? TrackChanged = null;

        public TrackControl()
        {
            InitializeComponent();
        }


        public void SetTrack(Models.Track track)
        {
            _track = track;

            UpdateDisplay();
        }

        public void SetInstrument(int instrumentNumber)
        {
            _instrumentNumber = instrumentNumber;
        }

        private void UpdateDisplay()
        {
            Display.Content = $"Not Implemented";
        }

        private void OctUp_Click(object sender, RoutedEventArgs e)
        {
            if (_track != null)
            {
                foreach(var n in _track.Notes)
                {
                    if (n.NoteNum > 1)
                    {
                        n.NoteNum += 12;
                    }
                }
            }

            FireEvent();
        }

        private void OctDown_Click(object sender, RoutedEventArgs e)
        {
            if (_track != null)
            {
                foreach (var n in _track.Notes)
                {
                    if (n.NoteNum > 1)
                    {
                        n.NoteNum -= 12;
                    }
                }
            }

            FireEvent();
        }

        private void FireEvent()
        {
            TrackChanged?.Invoke(this, new TrackControlTradeUpdateEventArgs());
        }

        private void Import_Click(object sender, RoutedEventArgs e)
        {
            if (!Clipboard.ContainsText())            
                return;
           
            if (_track == null)
                return;

            var clipboard = Clipboard.GetText();

            var lines = clipboard.Split("\n");

            var cnt = 0;
            foreach(var line in lines)
            {
                // we'er looking for the note and then octive number.
                var regex = new Regex(@"[ABCDEFG][-#]\d");

                var match = regex.Match(line);

                if (match.Success)
                {
                    var toParse = match.Value;

                    if (cnt < _track.TrackLength)
                    {
                        var notenum = "C-C#D-D#E-F-F#G-G#A-A#B-".IndexOf(toParse.Substring(0, 2)) / 2;

                        if (notenum < 0)
                            continue;

                        var octive = int.Parse(toParse.Substring(2, 1));

                        notenum += octive * 12;

                        _track.Notes[cnt].NoteNum = notenum;
                        _track.Notes[cnt].InstrumentNumber = _instrumentNumber;
                    }
                }

                cnt++;
            }

            FireEvent();
        }

        private void Copy_Click(object sender, RoutedEventArgs e)
        {
            _copiedTrack = _track;
        }

        private void Paste_Click(object sender, RoutedEventArgs e)
        {
            if (_copiedTrack == null)
                return;

            if (_track == null)
                return;

            var i = 0;
            foreach(var note in _copiedTrack.Notes)
            {
                _track.Notes[i++] = note.Clone();

                if (i > _track.Notes.Length)
                    return;
            }

            FireEvent();
        }
    }
}
