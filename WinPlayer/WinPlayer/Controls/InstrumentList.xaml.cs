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
using WinPlayer.Models;

namespace WinPlayer.Controls
{
    public class InstrumentChangeEventArgs : EventArgs
    {
        public Models.Instrument Instrument { get; set; }

        public InstrumentChangeEventArgs(Models.Instrument instrument)
        {
            Instrument = instrument;
        }
    }

    public class InstrumentListChangeEventArgs : EventArgs
    {
    }

    public class BlankEventArgs : EventArgs { }

    public partial class InstrumentList : UserControl
    {
        public event EventHandler<InstrumentChangeEventArgs>? InstrumentChange = null;
        public event EventHandler<InstrumentListChangeEventArgs>? InstrumentListChange = null;

        public event EventHandler<BlankEventArgs>? BeforeNewClick = null;
        public event EventHandler<BlankEventArgs>? AfterNewClick = null;

        private List<Models.Instrument> _value = new List<Models.Instrument>();
        public List<Models.Instrument> Value
        {
            get => _value;
            set
            {
                _value = value;
                InstrumentsList.ItemsSource = Value;
            }
        }

        public InstrumentList()
        {
            InitializeComponent();
        }

        private void NewButton_Click(object sender, RoutedEventArgs e)
        {
            BeforeNewClick?.Invoke(this, new BlankEventArgs());

            var instrument = new Models.Instrument();

            if (_value.Any())
            {
                var maxId = _value.Max(i => i.InstrumentNumber) + 1;
                instrument.InstrumentNumber = maxId;
            }

            var window = new InstrumentWindow();

            window.ShowDialog(instrument);

            Value.Add(instrument);

            InstrumentsList.ItemsSource = new List<Models.Instrument>();
            InstrumentsList.ItemsSource = Value;

            InstrumentListChange?.Invoke(this, new InstrumentListChangeEventArgs());

            AfterNewClick?.Invoke(this, new BlankEventArgs());
        }

        private void InstrumentsList_MouseDoubleClick(object sender, MouseButtonEventArgs e)
        {
            BeforeNewClick?.Invoke(this, new BlankEventArgs());

            var instrument = (Models.Instrument)InstrumentsList.SelectedItem;

            var window = new InstrumentWindow();

            window.ShowDialog(instrument);

            InstrumentsList.ItemsSource = new List<Models.Instrument>();
            InstrumentsList.ItemsSource = Value;

            AfterNewClick?.Invoke(this, new BlankEventArgs());
        }

        private void InstrumentsList_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (e.AddedItems.Count == 0)
                return;

            var instrument = e.AddedItems[0] as Models.Instrument;

            if (instrument == null)
                return;

            InstrumentChange?.Invoke(this, new InstrumentChangeEventArgs(instrument));
        }
    }
}
