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
    /// <summary>
    /// Interaction logic for EnvelopePoint.xaml
    /// </summary>
    public partial class EnvelopePoint : UserControl
    {
        private int _time = 0;
        private int _volume = 0;
        private int _width = 0;

        public EnvelopePoint()
        {
            InitializeComponent();
        }

        private void Time_TextChanged(object sender, TextChangedEventArgs e)
        {
            int.TryParse(Time.Text, out _time);
        }

        private void Volume_TextChanged(object sender, TextChangedEventArgs e)
        {
            int.TryParse(Volume.Text, out _volume);
        }

        private void Width_TextChanged(object sender, TextChangedEventArgs e)
        {
            int.TryParse(Width.Text, out _width);
        }

        public (int Time, int Volume, int Width) Value
        {
            get => (_time, _volume, _width);
            set {
                _time = value.Time;
                Time.Text = _time.ToString();
                _volume = value.Volume;
                Volume.Text = _volume.ToString();
                _width = value.Width;
                Width.Text = _width.ToString();
            }
        }

        public bool TimeIsEnabled
        {
            get => Time.IsEnabled;
            set => Time.IsEnabled = value;
        }
    }
}
