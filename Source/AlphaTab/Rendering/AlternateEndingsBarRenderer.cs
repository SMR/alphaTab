﻿/*
 * This file is part of alphaTab.
 * Copyright (c) 2014, Daniel Kuschny and Contributors, All rights reserved.
 * 
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3.0 of the License, or at your option any later version.
 * 
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library.
 */
using AlphaTab.Collections;
using AlphaTab.Model;
using AlphaTab.Platform;
using AlphaTab.Rendering.Glyphs;
using AlphaTab.Rendering.Layout;

namespace AlphaTab.Rendering
{
    /// <summary>
    /// This bar renderer can render repeat endings.
    /// </summary>
    public class AlternateEndingsBarRenderer : BarRendererBase
    {
        private const float Padding = 3;

        private readonly FastList<int> _endings;
        private string _endingsString;

        public AlternateEndingsBarRenderer(Bar bar)
            : base(bar)
        {
            var alternateEndings = Bar.MasterBar.AlternateEndings;
            _endings = new FastList<int>();
            for (var i = 0; i < MasterBar.MaxAlternateEndings; i++)
            {
                if ((alternateEndings & (0x01 << i)) != 0)
                {
                    _endings.Add(i);
                }
            }
            IsEmpty = _endings.Count == 0;
        }

        protected override void CreateBeatGlyphs()
        {
            for (int v = 0; v < Bar.Voices.Count; v++)
            {
                CreateVoiceGlyphs(Bar.Voices[v]);
            }
        }

        private void CreateVoiceGlyphs(Voice voice)
        {
            for (int i = 0, j = voice.Beats.Count; i < j; i++)
            {
                var b = voice.Beats[i];
                // we create empty glyphs as alignment references and to get the 
                // effect bar sized
                var container = new BeatContainerGlyph(b, GetOrCreateVoiceContainer(voice));
                container.PreNotes = new BeatGlyphBase();
                container.OnNotes = new BeatOnNoteGlyphBase();
                AddBeatGlyph(container);
            }
        }

        public override void DoLayout()
        {
            base.DoLayout();
            if (Index == 0)
            {
                Staff.TopSpacing = 5;
                Staff.BottomSpacing = 4;
            }
            Height = Resources.WordsFont.Size;

            var endingsStrings = new StringBuilder();
            for (int i = 0, j = _endings.Count; i < j; i++)
            {
                endingsStrings.Append(_endings[i] + 1);
                endingsStrings.Append(". ");
            }
            _endingsString = endingsStrings.ToString();
        }

        public override void Paint(float cx, float cy, ICanvas canvas)
        {
            base.Paint(cx, cy, canvas);

            if (_endings.Count > 0)
            {
                var res = Resources;
                canvas.Font = res.WordsFont;
                canvas.MoveTo(cx + X, cy + Y + Height);
                canvas.LineTo(cx + X, cy + Y);
                canvas.LineTo(cx + X + Width, cy + Y);
                canvas.Stroke();

                canvas.FillText(_endingsString, cx + X + Padding * Scale, cy + Y * Scale);
            }
        }
    }
}
