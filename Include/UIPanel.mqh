//+------------------------------------------------------------------+
//|                                              UIPanel.mqh         |
//|                      Modern UI Panel for EA Dashboard           |
//|                Display Real-time Trading Information             |
//+------------------------------------------------------------------+
#property copyright "2025"
#property strict

//+------------------------------------------------------------------+
//| UI Panel Class                                                   |
//+------------------------------------------------------------------+
class CUIPanel
{
private:
   string            m_panelName;
   int               m_x;
   int               m_y;
   int               m_width;
   int               m_height;
   color             m_bgColor;
   color             m_borderColor;
   color             m_textColor;
   int               m_fontSize;
   bool              m_visible;

   // Panel elements
   string            m_labels[];
   string            m_values[];
   int               m_elementCount;

   // Colors for status
   color             m_colorPositive;
   color             m_colorNegative;
   color             m_colorNeutral;

public:
   //--- Constructor
   CUIPanel()
   {
      m_panelName = "EA_Panel";
      m_x = 20;
      m_y = 50;
      m_width = 350;
      m_height = 500;
      m_bgColor = clrBlack;
      m_borderColor = clrGold;
      m_textColor = clrWhite;
      m_fontSize = 9;
      m_visible = true;
      m_elementCount = 0;

      m_colorPositive = clrLimeGreen;
      m_colorNegative = clrRed;
      m_colorNeutral = clrGray;

      ArrayResize(m_labels, 30);
      ArrayResize(m_values, 30);
   }

   //--- Destructor
   ~CUIPanel()
   {
      DeletePanel();
   }

   //--- Initialize panel
   bool Init(string panelName = "EA_Panel", int x = 20, int y = 50)
   {
      m_panelName = panelName;
      m_x = x;
      m_y = y;

      CreatePanel();
      return true;
   }

   //--- Create panel objects
   void CreatePanel()
   {
      // Main background
      CreateRectangle(m_panelName + "_BG", 0, 0, m_width, m_height,
                      m_bgColor, m_borderColor);

      // Header
      CreateRectangle(m_panelName + "_Header", 0, 0, m_width, 40,
                      clrDarkSlateGray, m_borderColor);

      CreateLabel(m_panelName + "_Title", 10, 10,
                  "GOLD MACD TREND EA", clrGold, 12, true);

      // Status indicator
      CreateRectangle(m_panelName + "_StatusBG", m_width - 25, 10, 20, 20,
                      clrDarkGreen, clrWhite);

      m_visible = true;
   }

   //--- Update panel with current data
   void Update(string signal,
               double signalStrength,
               double balance,
               double equity,
               double profit,
               int positions,
               double drawdown,
               double marginUsed,
               bool tradingEnabled,
               string timeFilter)
   {
      if(!m_visible)
         return;

      int yPos = 50;
      int lineHeight = 20;

      // Clear previous labels
      DeleteLabels();
      m_elementCount = 0;

      // Trading Status
      CreateSectionHeader("TRADING STATUS", yPos);
      yPos += lineHeight;

      color statusColor = tradingEnabled ? m_colorPositive : m_colorNegative;
      string statusText = tradingEnabled ? "ACTIVE" : "STOPPED";
      CreateInfoLine("Status:", statusText, yPos, statusColor);
      yPos += lineHeight;

      // Signal Information
      yPos += 5;
      CreateSectionHeader("SIGNAL ANALYSIS", yPos);
      yPos += lineHeight;

      color signalColor = m_colorNeutral;
      if(signal == "BUY")
         signalColor = m_colorPositive;
      else if(signal == "SELL")
         signalColor = m_colorNegative;

      CreateInfoLine("Signal:", signal, yPos, signalColor);
      yPos += lineHeight;

      CreateInfoLine("Strength:", DoubleToString(signalStrength, 1) + "%", yPos);
      yPos += lineHeight;

      // Account Information
      yPos += 5;
      CreateSectionHeader("ACCOUNT INFO", yPos);
      yPos += lineHeight;

      CreateInfoLine("Balance:", "$" + DoubleToString(balance, 2), yPos);
      yPos += lineHeight;

      CreateInfoLine("Equity:", "$" + DoubleToString(equity, 2), yPos);
      yPos += lineHeight;

      color profitColor = (profit >= 0) ? m_colorPositive : m_colorNegative;
      CreateInfoLine("Profit:", "$" + DoubleToString(profit, 2), yPos, profitColor);
      yPos += lineHeight;

      // Risk Management
      yPos += 5;
      CreateSectionHeader("RISK MANAGEMENT", yPos);
      yPos += lineHeight;

      color ddColor = (drawdown < 3.0) ? m_colorPositive :
                      (drawdown < 5.0) ? clrOrange : m_colorNegative;
      CreateInfoLine("Drawdown:", DoubleToString(drawdown, 2) + "%", yPos, ddColor);
      yPos += lineHeight;

      color marginColor = (marginUsed < 50.0) ? m_colorPositive :
                          (marginUsed < 70.0) ? clrOrange : m_colorNegative;
      CreateInfoLine("Margin Used:", DoubleToString(marginUsed, 1) + "%", yPos, marginColor);
      yPos += lineHeight;

      // Positions
      yPos += 5;
      CreateSectionHeader("POSITIONS", yPos);
      yPos += lineHeight;

      CreateInfoLine("Open:", IntegerToString(positions), yPos);
      yPos += lineHeight;

      // Time Filter
      yPos += 5;
      CreateSectionHeader("TIME FILTER", yPos);
      yPos += lineHeight;

      CreateInfoLine("Status:", timeFilter, yPos);
      yPos += lineHeight;

      // Footer
      yPos += 10;
      CreateLabel(m_panelName + "_Footer", 10, yPos,
                  "Last Update: " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                  clrGray, 8);

      // Update status indicator
      color indicatorColor = tradingEnabled ? clrLimeGreen : clrRed;
      ObjectSetInteger(0, m_panelName + "_StatusBG", OBJPROP_BGCOLOR, indicatorColor);

      ChartRedraw();
   }

   //--- Create section header
   void CreateSectionHeader(string text, int yPos)
   {
      string name = m_panelName + "_Header_" + IntegerToString(m_elementCount++);
      CreateLabel(name, 10, yPos, text, clrGold, 9, true);
   }

   //--- Create info line (label: value)
   void CreateInfoLine(string label, string value, int yPos, color valueColor = clrWhite)
   {
      string labelName = m_panelName + "_Label_" + IntegerToString(m_elementCount++);
      string valueName = m_panelName + "_Value_" + IntegerToString(m_elementCount++);

      CreateLabel(labelName, 15, yPos, label, clrLightGray, m_fontSize);
      CreateLabel(valueName, 180, yPos, value, valueColor, m_fontSize, true);
   }

   //--- Create rectangle
   void CreateRectangle(string name, int x, int y, int width, int height,
                        color bgColor, color borderColor)
   {
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);

      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x + x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y + y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, width);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, height);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, name, OBJPROP_COLOR, borderColor);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   //--- Create label
   void CreateLabel(string name, int x, int y, string text,
                    color textColor, int fontSize = 9, bool bold = false)
   {
      if(ObjectFind(0, name) >= 0)
         ObjectDelete(0, name);

      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, m_x + x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, m_y + y);
      ObjectSetInteger(0, name, OBJPROP_COLOR, textColor);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   }

   //--- Delete all labels except permanent ones
   void DeleteLabels()
   {
      for(int i = 0; i < m_elementCount; i++)
      {
         ObjectDelete(0, m_panelName + "_Header_" + IntegerToString(i));
         ObjectDelete(0, m_panelName + "_Label_" + IntegerToString(i));
         ObjectDelete(0, m_panelName + "_Value_" + IntegerToString(i));
      }
      ObjectDelete(0, m_panelName + "_Footer");
   }

   //--- Delete entire panel
   void DeletePanel()
   {
      DeleteLabels();
      ObjectDelete(0, m_panelName + "_BG");
      ObjectDelete(0, m_panelName + "_Header");
      ObjectDelete(0, m_panelName + "_Title");
      ObjectDelete(0, m_panelName + "_StatusBG");
   }

   //--- Show/Hide panel
   void Show() { m_visible = true; CreatePanel(); }
   void Hide() { m_visible = false; DeletePanel(); }
   bool IsVisible() { return m_visible; }

   //--- Setters
   void SetPosition(int x, int y) { m_x = x; m_y = y; }
   void SetColors(color bg, color border, color text)
   {
      m_bgColor = bg;
      m_borderColor = border;
      m_textColor = text;
   }
};
