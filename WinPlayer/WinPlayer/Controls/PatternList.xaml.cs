using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
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
    public class PatternChangeEventArgs : EventArgs
    {
        public Models.Pattern Pattern { get; set; }

        public PatternChangeEventArgs(Models.Pattern pattern)
        {
            Pattern = pattern;
        }
    }
    public class PatternListChangeEventArgs : EventArgs
    {
    }

    public class PatternLengthChangeEventArgs : EventArgs
    {        
    }

    public partial class PatternList : UserControl
    {
        public PatternList()
        {
            InitializeComponent();
        }

        public event EventHandler<PatternChangeEventArgs>? PatternChange = null;
        public event EventHandler<PatternListChangeEventArgs>? PatternListChange = null;
        public event EventHandler<PatternLengthChangeEventArgs>? PatternLengthChange = null;

        public event EventHandler<BlankEventArgs>? BeforeNewClick = null;
        public event EventHandler<BlankEventArgs>? AfterNewClick = null;

        private Models.Pattern? _pattern;

        private List<Models.Pattern> _value = new ();
        public List<Models.Pattern> Value
        {
            get => _value;
            set
            {
                _value = value;
                PatternsList.ItemsSource = Value;
                _pattern = _value[0];
                DisplayPattern();
            }
        }

        private void NewButton_Click(object sender, RoutedEventArgs e)
        {
            BeforeNewClick?.Invoke(this, new BlankEventArgs());

            var pattern = new Models.Pattern();
            _pattern = pattern;

            pattern.Speed = 3;
            pattern.TrackLength = 64;

            for (var i = 0; i < 16; i++)
                pattern.Tracks.Add(new Models.Track());

            if (_value.Any())
            {
                var maxId = _value.Max(i => i.Number) + 1;
                pattern.Number = maxId;
            }

            _value.Add(pattern);

            PatternsList.ItemsSource = new List<Models.Instrument>();
            PatternsList.ItemsSource = _value;

            PatternListChange?.Invoke(this, new PatternListChangeEventArgs());

            AfterNewClick?.Invoke(this, new BlankEventArgs());
            DisplayPattern();
        }

        private void PatternList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (e.AddedItems.Count == 0)
                return;

            var pattern = e.AddedItems[0] as Models.Pattern;

            if (pattern == null)
                return;

            _pattern = pattern;
            PatternChange?.Invoke(this, new PatternChangeEventArgs(pattern));
            DisplayPattern();
        }

        private void DisplayPattern()
        {
            if (_pattern == null) throw new Exception();
            PatternSpeed.Text = _pattern.Speed.ToString();
            PatternLength.Text = _pattern.TrackLength.ToString();
        }

        private void PatternSpeed_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (_pattern == null) return;

            if (int.TryParse(PatternSpeed.Text, out var speed))
            {
                _pattern.Speed = speed;
            }
        }

        // not on change as its destructive
        private void ApplyButton_Click(object sender, RoutedEventArgs e)
        {
            if (_pattern == null) throw new Exception();

            if (int.TryParse(PatternLength.Text, out var length))
            {
                if (length == 0)
                    return;

                _pattern.TrackLength = length;

                foreach(var track in _pattern.Tracks)
                {
                    var tmp = track.Notes;
                    track.Notes = new Models.Note[length];
                    track.TrackLength = length;

                    for(var i = 0; i < Math.Min(tmp.Length, length); i++)
                    {
                        track.Notes[i] = tmp[i];
                    }

                    if (length > tmp.Length)
                    {
                        for (var i = tmp.Length; i < length; i++)
                        {
                            track.Notes[i] = new Models.Note();
                        }
                    }
                }

                PatternLengthChange?.Invoke(this, new PatternLengthChangeEventArgs());
            }
        }
    }
}
