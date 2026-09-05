// T17.21 readable order identity. Pure codec; old BDR/BDP remain readable.
// digits-tested: unitless integer identifiers; price digits are not used.
#ifndef BD_ORDER_COMMENT_CODEC_MQH
#define BD_ORDER_COMMENT_CODEC_MQH

int OC_LegacyField(const string text, const string key)
{
   int p = StringFind(text, key);
   if(p < 0) return -1;
   int start = p + StringLen(key);
   int end = StringFind(text, "|", start);
   string token = end < 0 ? StringSubstr(text, start) : StringSubstr(text, start, end-start);
   return token == "" ? -1 : (int)StringToInteger(token);
}

int OC_UInt(const string text)
{
   if(StringLen(text) == 0) return -1;
   long value = 0;
   for(int i=0; i<StringLen(text); i++)
   {
      int c = (int)StringGetCharacter(text,i);
      if(c < 48 || c > 57) return -1;
      value = value*10 + c-48;
      if(value > 2147483647) return -1;
   }
   return (int)value;
}

int OC_PipeField(const string text, const string key)
{
   int p = StringFind(text, "|"+key);
   if(p < 0) return -1;
   int start = p + StringLen(key) + 1;
   int end = StringFind(text, "|", start);
   return OC_UInt(end < 0 ? StringSubstr(text,start) : StringSubstr(text,start,end-start));
}

int OC_RhRound(const string text)
{
   if(StringFind(text,"RH-") == 0) return 0;
   if(StringFind(text,"RHSL") != 0) return -1;
   int end = StringFind(text,"-",4);
   return end < 0 ? -1 : OC_UInt(StringSubstr(text,4,end-4));
}

int OC_RhCycle(const string text)
{
   if(StringFind(text,"BDR|C=") == 0) return OC_LegacyField(text,"BDR|C=");
   int dash = StringFind(text,"-");
   if(dash < 0) return -1;
   string label = StringSubstr(text,0,dash);
   if(label != "RH" && label != "RHSL?" &&
      !(StringFind(label,"RHSL") == 0 && OC_UInt(StringSubstr(label,4)) > 0)) return -1;
   string side = StringSubstr(text,dash,4);
   if(side == "-S|G") return 1; // SELL RH protects BUY Core
   if(side == "-B|G") return 2; // BUY RH protects SELL Core
   return -1;
}

int OC_RhGeneration(const string text)
{
   if(StringFind(text,"BDR|C=") == 0) return OC_LegacyField(text,"|G=");
   return OC_RhCycle(text) > 0 ? OC_PipeField(text,"G") : -1;
}

int OC_RhBundle(const string text)
{
   if(StringFind(text,"BDR|C=") == 0) return OC_LegacyField(text,"|B=");
   int generation = OC_RhGeneration(text);
   if(generation < 1) return -1;
   int bundle = OC_PipeField(text,"B");
   return StringFind(text,"|B") < 0 ? generation : bundle;
}

bool OC_RhMatchesCycle(const string text, const int cycle)
{
   if(cycle != 1 && cycle != 2) return false;
   // Preserve exact legacy prefix matching, including its trailing separator.
   if(StringFind(text,"BDR|C=") == 0)
      return StringFind(text,"BDR|C="+IntegerToString(cycle)+"|") == 0;
   return OC_RhCycle(text) == cycle && OC_RhGeneration(text) > 0 && OC_RhBundle(text) > 0;
}

bool OC_RhMatchesBundle(const string text, const int cycle,
                        const int generation, const int bundle)
{
   if(StringFind(text,"BDR|C=") == 0)
      return StringFind(text,"BDR|C="+IntegerToString(cycle)+"|G="+
                        IntegerToString(generation)+"|B="+IntegerToString(bundle)+"|") == 0;
   return OC_RhMatchesCycle(text,cycle) && OC_RhGeneration(text)==generation && OC_RhBundle(text)==bundle;
}

int OC_NextRhRound(const bool afterProtectiveReset, const bool hasLiveGeneration,
                    const bool latestKnown, const int latestRound,
                    const int latestGeneration, const int generation)
{
   if(!afterProtectiveReset) return 0;
   if(!latestKnown || latestRound < 0) return -1;
   if(hasLiveGeneration || generation > latestGeneration) return latestRound;
   return latestRound < 2147483647 ? latestRound+1 : -1;
}

string OC_BuildRh(const int cycle, const int generation, const int bundle,
                   const int stage, const int child, const int round)
{
   string label = round == 0 ? "RH" : (round > 0 ? "RHSL"+IntegerToString(round) : "RHSL?");
   string identity = (cycle == 1 ? "-S|G" : "-B|G")+IntegerToString(generation);
   if(bundle != generation) identity += "|B"+IntegerToString(bundle);
   string detail = (stage > 0 ? "|P"+IntegerToString(stage) : "")+"|N"+IntegerToString(child);
   string result = label+identity+detail;
   if(StringLen(result) <= 31) return result;
   // Broker limit: retain exact ownership identity; optional display detail can
   // be omitted for extreme integer IDs. Never truncate generation/bundle.
   result = label+identity;
   if(StringLen(result) <= 31) return result;
   return (round == 0 ? "RH" : "RHSL?")+identity;
}

bool OC_IsPyramid(const string text)
{
   if(StringFind(text,"BDP|") == 0) return true;
   if(StringFind(text,"PYR-B#") != 0 && StringFind(text,"PYR-S#") != 0) return false;
   return OC_UInt(StringSubstr(text,6)) > 0;
}

int OC_PyramidDirection(const string text)
{
   if(StringFind(text,"BDP|") == 0) return OC_LegacyField(text,"D=");
   if(!OC_IsPyramid(text)) return -1;
   return StringFind(text,"PYR-B#") == 0 ? 0 : 1;
}

int OC_PyramidLevel(const string text)
{
   if(StringFind(text,"BDP|") == 0) return OC_LegacyField(text,"L=");
   return OC_IsPyramid(text) ? OC_UInt(StringSubstr(text,6)) : -1;
}

string OC_BuildPyramid(const int direction, const int level)
{
   return (direction == 0 ? "PYR-B#" : "PYR-S#")+IntegerToString(level);
}
#endif
