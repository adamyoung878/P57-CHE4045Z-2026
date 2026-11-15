*==============================================================================================================
*P57 GAMS MODEL
*==============================================================================================================
*Run options (gams base_model.gms --NAME=value):
*  --COAL       Coalition solved: 1, 2, 3, 4, 12, 13, 14, 23, 24, 34, 123, 124, 134, 234 or 1234 (default 1234)
*  --BTCMULT    Multiplier on the bitcoin (BTC) price (cr_kBTC, default 1)
*  --DINDMULT   Multiplier on the minimum industrial demand D_ind (kDind, default 1)
*  --BGMULT     Multiplier on the biogas feedstock cost FeedCost('BG') (kBG, default 1)
*  --RG2, --RG3, --RG4  Weights of the EcO at the three inner MOO points (default 0.4, 0.5, 0.6)
*  --OBJ        Objective minimised: MOO (EcO and EnO weighted over RG, the default), EcO (economic objective) or EnO (environmental objective)
*  --START      Warm start: GDX of an earlier EcO solution of the same Coalition, its integers fixed (EcO and MOO runs)
*  --SEED, --SEEDPLAYER  With --START: take the design of player 1, 2, 3 or 4 from another solution (GDX) instead

$onEolcom
$if not set COAL $setGlobal COAL 1234
$if not set BTCMULT $setGlobal BTCMULT 1
$if not set DINDMULT $setGlobal DINDMULT 1
$if not set BGMULT $setGlobal BGMULT 1
$if not set RG2 $setGlobal RG2 0.4
$if not set RG3 $setGlobal RG3 0.5
$if not set RG4 $setGlobal RG4 0.6
$if not set OBJ $setGlobal OBJ MOO
$ifI not %OBJ% == EcO $ifI not %OBJ% == EnO $ifI not %OBJ% == MOO $abort --OBJ must be EcO, EnO or MOO

*==============================================================================================================
*PLAYERS AND COALITIONS
*==============================================================================================================
Sets
player              Players                     /1 Supply chain network and CHP (SCN-CHP),
                                                2 MEE,
                                                3 HEN,
                                                4 Crypto-mining Farm/
coal                Coalitions                  /1, 2, 3, 4, 12, 13, 14, 23, 24, 34, 123, 124, 134, 234, 1234/
mem(coal,player)    Players in each Coalition   /1.     1,
                                                2.      2,
                                                3.      3,
                                                4.      4,
                                                12.     (1,2),
                                                13.     (1,3),
                                                14.     (1,4),
                                                23.     (2,3),
                                                24.     (2,4),
                                                34.     (3,4),
                                                123.    (1,2,3),
                                                124.    (1,2,4),
                                                134.    (1,3,4),
                                                234.    (2,3,4),
                                                1234.   (1,2,3,4)/
mbr(player)         Members of the Coalition solved
act(coal)           Coalitions within the Coalition solved: their equations are in the model;

Singleton Set solved(coal) Coalition solved (--COAL) /%COAL%/;

mbr(player) = sum(solved, mem(solved,player));
act(coal)   = yes$(sum(player$(mem(coal,player) and not mbr(player)), 1) = 0);

*==============================================================================================================
*COMMON DATA
*==============================================================================================================
Sets
S_s     Steam supplier      /sp1, sp2, sp3/
SS_Data Steam data columns  /st_p, st_H, st_Tin, st_Tout, st_EI/;

*Columns: st_p price [$ per t]; st_Tin and st_Tout inlet and outlet temperature [C]; st_H enthalpy [kJ per kg];
*st_EI emission factor [kg CO2 per t]
Table   steam(S_s,SS_Data)  Steam bought from outside
            st_p    st_Tin  st_Tout st_H    st_EI
        sp1 17.6     257     256     2798.13 635.0
        sp2 15.3     196.6   195.6   2789.9  635.0
        sp3 13.2     154     153     2752.78 635.0;

Parameters
OH              Plant operating hours [h per year]                                  /8160/
HY              Calendar hours [h per year]                                         /8760/
EcOunit         Unit of every EcO variable and of the objective [$ per year]        /1e5/
FX              Mean European Central Bank rate from Oct 2025 to Sep 2026 [R per $] /16.5548/
D_ind           Minimum industrial demand [kW]                                      /5000/
kDind           Multiplier on the minimum industrial demand (--DINDMULT)            /%DINDMULT%/
kBG             Multiplier on the biogas feedstock cost (--BGMULT)                  /%BGMULT%/;

D_ind = kDind*D_ind;

Sets
Emissions_stream        Bought utilities with an emission factor    /Elec, HPS, MPS, LPS, CW/;

Parameters
CO2e(Emissions_stream)  Emission factor of each bought utility [t CO2e per MWh or per t]    /Elec 0.931,
                                                                                            HPS 0.3911,
                                                                                            MPS 0.3897,
                                                                                            LPS 0.3844,
                                                                                            CW 0.00034/;

*==============================================================================================================
*SCN: FUEL SUPPLY CHAIN
*==============================================================================================================
Sets
sp              Supply points               /CS corn stover,
                                             WP Forestry waste,
                                             BG Biogas,
                                             CL Coal/
f               Freight mode                /road, rail, pipe/
FreightCosts    Freight cost data columns   /FFC, VFC, AF, FIC, tau, RF/
s               Supply chain season         /s1, s2, s3/;

Table   capacity(sp,s) Capacity of the supply points by season [kg per season]
            s1          s2          s3
        CS  3000000     4500000     2000000
        WP  250000000   210000000   30000000
        BG  450000000   500000000   2000000000
        CL  50000000    50000000    50000000;

Table   FeedCost(sp,s) Cost of feedstock from each supply point in each season [$ per kg]
            s1          s2          s3
        CS  0.024       0.022       0.027
        WP  0.04        0.045       0.025
        BG  0.05        0.03        0.07
        CL  0.9         0.9         0.9;

*FFC: fixed freight cost [$ per kg]; VFC: variable freight cost [$ per kg.km]; AF: annualisation factor [1 per year];
*FIC: freight investment cost [$ per km]; tau: tortuosity factor; RF: return trip factor
Table   FreightCost(f,FreightCosts) Freight cost data
                FFC     VFC         AF      FIC     tau     RF
        road    0.002   0.00009     0.2     5000    1.27    2
        rail    0.005   0.000007    0.25    50000   1.1     2
        pipe    0.001   0.000001    0.50    150000  1.27    1;

Parameters
DS(s)       Duration of season as a fraction of the year                        /s1 0.35,
                                                                                s2 0.35,
                                                                                s3 0.3/
NC(sp)      Net calorific value [kWh per kg]                                    /CS 4.63,
                                                                                WP 4.95,
                                                                                BG 5.08,
                                                                                CL 7.20/
BE          Boiler efficiency                                                   /0.75/
d(sp)       Distance between supply points and power generation point [km]      /CS 30,
                                                                                WP 50,
                                                                                BG 38,
                                                                                CL 100/
Ccomp(sp)   Carbon composition of fuel type [kg C per kg fuel]                  /CS 0.47,
                                                                                WP 0.458,
                                                                                BG 0.563,
                                                                                CL 0.775/
RO          Ratio of CO2 to carbon on oxidation (44 over 12) [kg CO2 per kg C]  /3.67/
Emf(f)      Emission factor [g CO2 per t.km]                                    /road 72,
                                                                                rail 35/;

FeedCost('BG',s) = kBG*FeedCost('BG',s);

Positive Variables
TFC(f,sp,s) Feedstock and variable freight cost per season [$ per season]
TFC2(f,sp)  Annualised freight investment cost [$ per year]
TFC2_SUM    Total annualised freight investment cost [$ per year]
x(sp,f,s)   Boiler heat output from fuel sp via freight f in season s with BE applied [kW]
bb(sp,s)    Boiler heat output from fuel sp in season s [kW]
EmT(f)      Transport CO2 by freight mode [t per year]
EmB(sp)     Boiler CO2 by fuel [kt per year]
EmissionsT  Transport CO2 [t per year]
EmissionsB  Boiler CO2 [kt per year];

Binary Variables
z(sp,f)     Freight link from supply point sp by mode f is built;

Equations
Supply(sp,s)            Boiler heat from sp within its seasonal supply
demand(sp,s)            Boiler heat from sp is the sum over freight modes
FreightCap(sp,f,s)      No freight on a link that is not built
TotalFuelCost(f,sp,s)   Feedstock and variable freight cost
TotalFuelCost2(f,sp)    Annualised freight investment cost
Etfc2                   Total annualised freight investment cost
EEmT(f)                 Transport CO2 by freight mode
EEmissionsT             Total transport CO2
EEmB(sp)                Boiler CO2 by fuel
EEmissionsB             Total boiler CO2;

Supply(sp,s)$act('1')..
    sum((f), x(sp,f,s)) =l= capacity(sp,s)*BE*NC(sp)/(OH*DS(s));
demand(sp,s)$act('1')..
    sum((f), x(sp,f,s)) =e= bb(sp,s);
FreightCap(sp,f,s)$act('1')..
    x(sp,f,s) =l= capacity(sp,s)*z(sp,f)*BE*NC(sp)/(OH*DS(s));

TotalFuelCost(f,sp,s)$act('1')..
    TFC(f,sp,s) =e= ((FreightCost(f,'FFC') + (FreightCost(f,'VFC')*FreightCost(f,'RF')*FreightCost(f,'tau')*d(sp)))*x(sp,f,s)/(BE*NC(sp)/(OH*DS(s))) + (FeedCost(sp,s) * x(sp,f,s)/(BE*NC(sp)/(OH*DS(s)))));
TotalFuelCost2(f,sp)$act('1')..
    TFC2(f,sp) =e= (FreightCost(f,'AF')*FreightCost(f,'FIC') * FreightCost(f,'tau')*z(sp,f)*d(sp));
Etfc2$act('1')..
    TFC2_SUM =e= sum((f,sp), TFC2(f,sp));

EEmT(f)$act('1')..
    EmT(f) =e= sum((sp,s), x(sp,f,s)/(BE*NC(sp)/(OH*DS(s)))*d(sp)*FreightCost(f,'tau')*Emf(f))/1e9;
EEmissionsT$act('1')..
    EmissionsT =e= sum(f, EmT(f));

EEmB(sp)$act('1')..
    EmB(sp) =e= sum((f,s), x(sp,f,s)/(BE*NC(sp)/(OH*DS(s)))*Ccomp(sp)*RO)/1e6;
EEmissionsB$act('1')..
    EmissionsB =e= sum(sp, EmB(sp));

z.fx('WP','pipe') = 0;
z.fx('CL','pipe') = 0;
z.fx('CS','pipe') = 0;

*==============================================================================================================
*CHP: TURBINES, BOILER AND STEAM HEADERS
*==============================================================================================================
Sets
T   Turbines            /Tb1, Tb2/
Ws  Water streams       /ws1, ws2, ws3, ws4, ws5, ws6/
Stp Stream properties   /sTmp1, sTmp2, sE2, sCst/;

*Columns: sTmp1 and sTmp2 inlet and outlet temperature [C]; sE2 enthalpy [kJ per kg]; sCst cost [$ per m3]
Table   Streamproperties(Ws,Stp) Water stream data
                sTmp1   sTmp2   sE2     sCst
        ws1     30      30      125.7   0
        ws2     30      60      271.9   0
        ws3     120     85      0       0
        ws4     30      0       125.7   0
        ws5     25      80      0       0
        ws6     25      45      2675.57 0.016;

Parameters
MaxG(T)         Maximum turbine generative capacity [kW]                                    /Tb1 6250,
                                                                                            Tb2 9000/
MinG(T)         Minimum turbine generative capacity [kW]                                    /Tb1 2500,
                                                                                            Tb2 3000/
MaxInF(T)       Maximum inlet flow of each turbine [kg per s]
MaxCndF(T)      Maximum condensing flow of turbine 1 [kg per s]
MaxIntF(T)      Maximum flow through turbine 1 past its MPS extraction I1 - HE1 [kg per s]
MaxLPSout(T)    Maximum LPS exhaust of turbine 2 [kg per s]
h_LPS           Enthalpy of superheated LPS [kJ per kg]                                     /2910.76/
h_LPSd          Enthalpy of desuperheated LPS [kJ per kg]                                   /2752.78/
h_MPS           Enthalpy of superheated MPS [kJ per kg]                                     /2948.90/
h_MPSd          Enthalpy of desuperheated MPS [kJ per kg]                                   /2798.21/
h_HPS           Enthalpy of superheated HPS [kJ per kg]                                     /3162.89/
h_HPSd          Enthalpy of desuperheated HPS [kJ per kg]                                   /2798.90/
hw_ds           Enthalpy of the 25 C desuperheating spray water [kJ per kg]                 /104.93/
h_Cex           Enthalpy of turbine-1 condensing exhaust [kJ per kg]                        /2357.44/
h_fw            Feed-water enthalpy [kJ per kg];

MaxInF('Tb1')       = 87089.66/3600;
MaxInF('Tb2')       = 110676.45/3600;
MaxCndF('Tb1')      = 28122.70/3600;
MaxIntF('Tb1')      = 59874.144/3600;
MaxLPSout('Tb2')    = 64410.06/3600;
h_fw                = Streamproperties('ws1','sE2');

Positive Variables
I1                  Inlet flow to turbine 1 [kg per s]
I2                  Inlet flow to turbine 2 [kg per s]
HE1                 Turbine-1 extraction to the 195 psig MPS header [kg per s]
HE2                 Turbine-2 extraction to the 195 psig MPS header [kg per s]
LE1                 Turbine-1 exhaust to the 62 psig LPS header [kg per s]
LE2                 Turbine-2 exhaust to the 62 psig LPS header [kg per s]
C                   Turbine-1 condensing flow to its own condenser [kg per s]
P(T)                Power generated by each turbine [kW]
BF1                 Let-down from the 635 psig HPS header to the MPS header [kg per s]
BF2                 Let-down from the 195 psig MPS header to the LPS header [kg per s]
HPST                HPS raised in the boiler into the 635 psig header [kg per s]
MPS                 MPS leaving the 195 psig header [kg per s]
LPS                 LPS leaving the 62 psig header [kg per s]
Qb                  Boiler heat from fuel [kW]
InletflowHEN        HPS sent from the HPS header to the HEN before desuperheating [kg per s]
Q_crB               Crypto-Farm heat added to the boiler feed water [kW]
Q_fw                Solar heat added to the boiler feed water [kW]
SCN_CHP_Pw          CHP power above the demand and the Farm: wasted [kW]
CR_Pco              CHP power used by the crypto Farm [kW];

Equations
MaxGE(T)            Turbine power at most MaxG
MinGE(T)            Turbine power at least MinG
MaxInFE             Turbine-1 inlet limit
MaxInFE2            Turbine-2 inlet limit
MaxCndFE            Turbine-1 condensing-flow limit
MaxIntFE            Turbine-1 limit past the MPS extraction
MaxLPSoutE          Turbine-2 LPS exhaust limit
SeasonDuty(s)       Boiler heat from fuel is the same in every season
HPSb                Boiler energy balance: HPS from fuel heat plus solar and crypto-Farm preheat
M1                  HPS header balance
M2                  Turbine and let-down balance
M3                  Turbine-1 flow balance
M4                  Turbine-2 flow balance
M5                  MPS header balance
M6                  LPS header balance
PowerDemand         Turbines meet the minimum industrial demand D_ind
ESCN_CHP_Pw         CHP output serves the industrial demand and then the Farm and the rest is wasted
EB1                 Turbine-1 energy balance
EB2                 Turbine-2 energy balance;

*Power generation
MaxGE(T)$act('1')..
    P(T) =l= MaxG(T);
MinGE(T)$act('1')..
    P(T) =g= MinG(T);
MaxInFE$act('1')..
    I1 =l= MaxInF('Tb1');
MaxInFE2$act('1')..
    I2 =l= MaxInF('Tb2');
MaxCndFE$act('1')..
    C =l= MaxCndF('Tb1');
MaxIntFE$act('1')..
    I1 - HE1 =l= MaxIntF('Tb1');
MaxLPSoutE$act('1')..
    LE2 =l= MaxLPSout('Tb2');

*Boiler balance
SeasonDuty(s)$act('1')..
    sum(sp, bb(sp,s)) =e= Qb;
HPSb$act('1')..
    HPST*(h_HPS - h_fw) =e= Qb + Q_fw + Q_crB;

*Material balances
M1$act('1')..
    HPST - I2 - I1 - BF1-InletflowHEN =e= 0;
M2$act('1')..
    I1 + I2 + BF1 - C - MPS - LPS =e= 0;
M3$act('1')..
    I1 - HE1 - LE1 - C =e= 0;
M4$act('1')..
    I2 - HE2 - LE2 =e= 0;
M5$act('1')..
    HE1 + HE2 + BF1 - BF2 - MPS =e= 0;
M6$act('1')..
    LE1 + LE2 + BF2 - LPS =e= 0;

*Demand
PowerDemand$act('1')..
    P('Tb1') + P('Tb2') =g= D_ind;

*The CHP output serves D_ind, then the Farm (CR_Pco); the remainder SCN_CHP_Pw is wasted
ESCN_CHP_Pw$act('1')..
    P('Tb1') + P('Tb2') =e= D_ind + CR_Pco + SCN_CHP_Pw;

*Energy balances
EB1$act('1')..
    h_HPS*I1 - h_MPS*HE1 - h_LPS*LE1 - h_Cex*C - P('Tb1') =e= 0;
EB2$act('1')..
    h_HPS*I2 - h_MPS*HE2 - h_LPS*LE2 - P('Tb2') =e= 0;

*==============================================================================================================
*CHP: SOLAR FEED PREHEAT AND MAKE-UP WATER
*==============================================================================================================
Parameters
Ta          Ambient temperature [C]                                                     /32/
GHI         Global horizontal irradiation [kW per m2]                                   /0.8/
aa1         First-order heat-loss coefficient of the solar collector [kW per m2.K]      /0.00153/
aa2         Second-order heat-loss coefficient of the solar collector [kW per m2.K2]    /0.0000003/
n           Zero-loss efficiency of the solar collector                                 /0.764/
SPc         Solar panel cost [$ per m2]                                                 /100/
wc          Price of boiler water [$ per m3]                                            /0.15/
CP_s        Heat capacity of thermal storage stream [kJ per kg.K]                       /4.2/
r           Density of thermal storage stream [kg per m3]                               /1000/
U_st        Overall U of the storage exchanger (unsourced) [kW per m2.K]                /0.25/
CST         Cost per unit volume of thermal storage tank [$ per m3]                     /50/
CHE         Cost per unit area of the solar exchanger [$ per m2]                        /641.7/
CI          Cost exponent of the solar exchanger                                        /0.83/
epsHE       Area shift keeping the HE cost gradient finite at zero area [m2]            /1e-3/
HEI         Heat exchanger installation cost [$]                                        /8333.3/
HPSTmax     Upper bound on HPST from fuel supply with full solar and Farm preheat [kg per s]
dT1_HE1     Solar exchanger terminal difference at the ws2 inlet [K]
dT2_HE1     Solar exchanger terminal difference at the ws2 outlet [K]
LMTD_HE1    Log-mean temperature difference of the solar exchanger [K];

dT1_HE1     = Streamproperties('ws3','sTmp1') - Streamproperties('ws2','sTmp1');
dT2_HE1     = Streamproperties('ws3','sTmp2') - Streamproperties('ws2','sTmp2');
LMTD_HE1    = (dT1_HE1 - dT2_HE1)/log(dT1_HE1/dT2_HE1);

Positive Variables
Fws(Ws) Flow of each water stream [kg per s]
wD      Boiler make-up water [kg per s]
wTC     Make-up water cost [$ per year]
T_c     Average collector temperature [C]
ASP     Area of solar panel [m2]
VST     Volume of thermal storage tank [m3]
AHE1    Solar exchanger area [m2];

Binary Variables
S_A Solar preheat of the boiler feed is built;

Equations
WaterB      Boiler make-up water balance
WaterC      Make-up water cost [$ per year]
FeedQ       Solar heat added to the feed water
EFWS2       Preheated feed only when solar is built
EFWS3       Feed water is the cold plus the preheated stream
SpTc        Average collector temperature
AreaSP      Solar collector area
AreaHE1     Solar exchanger area
VolumeST    Thermal storage volume;

WaterB$act('1')..
    wD-C =e= HPST;
WaterC$act('1')..
    wTC =e= wD*wc*OH*3.6;
FeedQ$act('1')..
    Q_fw =e= Fws('ws2')*CP_s*(Streamproperties('ws2','sTmp2')-Streamproperties('ws2','sTmp1'));

EFWS2$act('1')..
    Fws('ws2') =l= HPSTmax*S_A;
EFWS3$act('1')..
    HPST =e= Fws('ws2') + Fws('ws1');

SpTc$act('1')..
    T_c =e= (((Streamproperties('ws2','sTmp1'))+(Streamproperties('ws2','sTmp2')))/2);
AreaSP$act('1')..
    ASP =e= ((Fws('ws2')*((Streamproperties('ws2','sTmp2'))-(Streamproperties('ws2','sTmp1')))*CP_s) + (Fws('ws5')*((Streamproperties('ws5','sTmp2'))-(Streamproperties('ws5','sTmp1')))*CP_s)) / ((n*GHI)-(aa1*(T_c-Ta))-(aa2*(T_c-Ta)*(T_c-Ta)));
AreaHE1$act('1')..
    AHE1 =e= Fws('ws2')*((Streamproperties('ws2','sTmp2'))-(Streamproperties('ws2','sTmp1')))*CP_s/(LMTD_HE1*U_st);
VolumeST$act('1')..
    VST =e= (((Fws('ws2')*((Streamproperties('ws2','sTmp2'))-(Streamproperties('ws2','sTmp1')))*CP_s)/2)/(CP_s*r*(Streamproperties('ws3','sTmp1')-Streamproperties('ws3','sTmp2'))));

*==============================================================================================================
*CHP: DESUPERHEATING AND CONDENSERS
*==============================================================================================================
Sets
Cndr    Condensers for LPS MPS and HPS  /cndL, cndM, cndH/
Stm     Steam streams                   /LPSs, MPSs, HPSs/
SStp    Steam properties                /sTemp1, sTemp2, sH1, sH2, sCp1/;

*Columns: sTemp1 and sTemp2 inlet and outlet temperature [C]; sH1 and sH2 inlet and outlet enthalpy [kJ per kg];
*sCp1 heat capacity [kJ per kg.K]
Table   St_Pr(Stm,SStp) Header steam properties
                sTemp1  sTemp2  sH1     sH2     sCp1
        LPSs    154.44  143.61  2752.78 2738.06 2.27
        MPSs    193.6   180     2948.90 2787
        HPSs    382.22  253     3162.89 2799    2.40;

Parameters
H_VapL          Enthalpy of vaporisation of LPS [kJ per kg]         /2122.72/
H_VapM          Enthalpy of vaporisation of MPS [kJ per kg]         /1965.18/
H_VapH          Enthalpy of vaporisation of HPS [kJ per kg]         /1690.7/
Tw_in           Cooling-water inlet temperature [C]                 /25/
Tw_out          Cooling-water outlet of the header condensers [C]   /45/
Cp_wt           Heat capacity of cooling water [kJ per kg.K]        /4.18/
AF_cnd          Annualisation factor of the condensers [1 per year] /0.322/
CF_cnd          Fixed cost of a condenser installation [$]          /13000/
AC_cnd          Area cost coefficient of the condensers [$ per m2]  /1000/
AE_cnd          Area cost exponent of the condensers                /0.83/
hf_CndC         Saturated liquid enthalpy at 0.1 bar [kJ per kg]    /191.81/
Ts_CndC         Saturation temperature at 0.1 bar [C]               /45.81/
TwC_out         Cooling-water outlet of the turbine-1 condenser [C] /35/
LMTD_CndC       Log-mean temperature difference of the turbine-1 condenser [K]
dT1_Hdr(Cndr)   Steam inlet less cooling-water outlet [K]
dT2_Hdr(Cndr)   Steam outlet less cooling-water inlet [K]
LMTD_Hdr(Cndr)  Log-mean temperature difference of the header condensers [K]
cw_Cnd(Cndr)    Cooling water per kg of steam condensed [kg per kg]
kA_Cnd(Cndr)    Condenser area per kg per s of cooling water [m2.s per kg];

LMTD_CndC       = ((Ts_CndC - Tw_in) - (Ts_CndC - TwC_out))/log((Ts_CndC - Tw_in)/(Ts_CndC - TwC_out));

dT1_Hdr('cndL') = St_Pr('LPSs','sTemp1') - Streamproperties('ws6','sTmp2');
dT2_Hdr('cndL') = St_Pr('LPSs','sTemp2') - Streamproperties('ws6','sTmp1');
dT1_Hdr('cndM') = St_Pr('MPSs','sTemp1') - Streamproperties('ws6','sTmp2');
dT2_Hdr('cndM') = St_Pr('MPSs','sTemp2') - Streamproperties('ws6','sTmp1');
dT1_Hdr('cndH') = St_Pr('HPSs','sTemp1') - Streamproperties('ws6','sTmp2');
dT2_Hdr('cndH') = St_Pr('HPSs','sTemp2') - Streamproperties('ws6','sTmp1');
LMTD_Hdr(Cndr)  = (dT1_Hdr(Cndr) - dT2_Hdr(Cndr))/log(dT1_Hdr(Cndr)/dT2_Hdr(Cndr));

cw_Cnd('cndL')  = H_VapL/(Cp_wt*(Tw_out-Tw_in));
cw_Cnd('cndM')  = H_VapM/(Cp_wt*(Tw_out-Tw_in));
cw_Cnd('cndH')  = H_VapH/(Cp_wt*(Tw_out-Tw_in));
kA_Cnd(Cndr)    = (Streamproperties('ws6','sTmp2') - Streamproperties('ws6','sTmp1'))*CP_s/(LMTD_Hdr(Cndr)*U_st);

Positive Variables
mw_ds1      Spray water to desuperheat the LPS [kg per s]
mw_ds2      Spray water to desuperheat the MPS [kg per s]
mw_ds3      Spray water to desuperheat the HPS sent to the HEN [kg per s]
MPSd        Desuperheated MPS including spray water [kg per s]
HPSd        Desuperheated HPS for the HEN including spray water [kg per s]
LPSd        Desuperheated LPS including spray water [kg per s]
Cl_WtC      Cooling water for the turbine-1 condenser [kg per s]
A_CndC      Turbine-1 condenser area [m2]
CndC_cst    Turbine-1 condenser capital cost [$ per year];

Equations
Emw_ds1     LPS spray water
emw_ds2     MPS spray water
Emw_ds3     HPS spray water
EMPSd       MPS after desuperheating
ELPSd       LPS after desuperheating
EHPSd       HPS for the HEN after desuperheating
EWt_C       Cooling water of the turbine-1 condenser
EA_CndC     Area of the turbine-1 condenser
ECndC_cst   Annualised cost of the turbine-1 condenser;

*Desuperheating
Emw_ds1$act('1')..
    mw_ds1 =e= (LPS*(h_LPS-h_LPSd))/(h_LPSd-hw_ds);
emw_ds2$act('1')..
    mw_ds2 =e= (MPS*(h_MPS-h_MPSd))/(h_MPSd-hw_ds);
Emw_ds3$act('1')..
    mw_ds3 =e= (InletflowHEN*(h_HPS-h_HPSd))/(h_HPSd-hw_ds);
EMPSd$act('1')..
    MPSd =e= MPS + mw_ds2;
ELPSd$act('1')..
    LPSd =e= LPS + mw_ds1;
EHPSd$act('1')..
    HPSd =e= InletflowHEN + mw_ds3;

*Turbine-1 condenser
EWt_C$act('1')..
    Cl_WtC =e= C*(h_Cex - hf_CndC)/(Cp_wt*(TwC_out - Tw_in));
EA_CndC$act('1')..
    A_CndC =e= C*(h_Cex - hf_CndC)/(U_st*LMTD_CndC);
ECndC_cst$act('1')..
    CndC_cst =e= AF_cnd*(CF_cnd + ((((A_CndC + epsHE)**AE_cnd) - (epsHE**AE_cnd))*AC_cnd));

*==============================================================================================================
*SCN-CHP: CAPITAL COST AND THE COST COMMON TO ALL ITS COALITIONS
*==============================================================================================================
Parameters
aBl     Boiler cost constant [$]    /130000/
bBl     Boiler cost coefficient     /53/
e1      Boiler cost exponent        /0.9/
aT      Turbine cost constant [$]   /-14000/
bT      Turbine cost coefficient    /1900/
e2      Turbine cost exponent       /0.75/
AF_CHP  Annualisation factor of the boiler and turbines [1 per year];

AF_CHP = AF_cnd;

Positive Variables
SA_cst  Solar capital cost [$]
CHP_cst Annualised boiler and turbine cost [$ per year];

Variables
SCN_CHP_com SCN-CHP cost common to all its Coalitions [$ per year];

Equations
ESA_cst         Solar capital cost
ECHP_cst        Annualised boiler and turbine cost
ESCN_CHP_com    SCN-CHP cost common to all its Coalitions;

ESA_cst$act('1')..
    SA_cst =e= (ASP*SPc)+(VST*CST)+((((AHE1 + epsHE)**CI) - (epsHE**CI))*CHE)+(HEI*S_A);

ECHP_cst$act('1')..
    CHP_cst =e= AF_CHP*(aBl + bBl*((HPST*3600 + epsHE)**e1) + sum(T, aT + bT*(P(T)**e2)));

ESCN_CHP_com$act('1')..
    SCN_CHP_com =e= sum((sp,f,s), TFC(f,sp,s)) + TFC2_SUM + wTC + SA_cst + CndC_cst + CHP_cst;

*==============================================================================================================
*MULTI-EFFECT EVAPORATOR (MEE)
*==============================================================================================================
Parameters
xF          Mass fraction of salt in the sea-water feed                             /0.035/
xB          Mass fraction of salt in the brine                                      /0.07/
TSteam      Inlet temperature of steam in the first effect [K]                      /373/
TVfinal     Condensation temperature of the final distillate [K]                    /308/
TV1         Temperature of first distillate [K]                                     /373/
U_a         Heating-tube U at 0 K: UHTFFEAC = U_a + U_b*TVavg [kW per m2.K]         /0.8552/
U_b         Slope of heating-tube U with TVavg [kW per m2.K2]                       /0.0047/
Lam_a       Latent heat at 0 K: LambdaAvg = Lam_a - Lam_b*TVavg [kJ per kg]         /3278.8/
Lam_b       Slope of latent heat with TVavg [kJ per kg.K]                           /2.7532/
GOR_f       Gain kept per effect: GOR = NEFF*GOR_f**NEFF                            /0.98/
epsGOR      Offset keeping Distflow over GOR finite                                 /1e-7/
C_evap      Evaporator cost coefficient: AFC = NEFF*C_evap*A**n_evap [$ per year]   /600/
n_evap      Evaporator cost exponent                                                /0.6/
Cp_sw       Heat capacity of the sea-water feed [kJ per kg.K]                       /4.0/
SF_d        Sea-water feed [kg per s]                                               /56/
T_swF       Sea-water feed temperature leaving the final condenser [C]
T_swH       Sea-water feed temperature into the first effect [C]                    /80/
T_stPH      Condensing temperature of the LPS in the sea-water preheater [C]
U_PH_HX     Overall U of the LPS sea-water preheater [kW per m2.K]                  /1.2/
AF_MEE      Annualisation factor of the MEE exchangers [1 per year]                 /0.322/
CF_MEE      Fixed cost per exchanger [$]                                            /13000/
AC_MEE      Area cost coefficient of the MEE exchangers [$ per m2]                  /1000/
AE_MEE      Area cost exponent of the MEE exchangers                                /0.83/
PH_duty     Preheat duty of the sea-water feed from T_swF to T_swH [kW];

T_swF   = TVfinal - 273;
T_stPH  = steam('sp3','st_Tin');
PH_duty = Cp_sw*SF_d*(T_swH - T_swF);

Positive Variables
SF              Sea-water feed [kg per s]
Brineflow       Brine flow [kg per s]
TVavg           Average distillate temperature [K]
DeltaTVac       Temperature drop per effect [K]
UHTFFEAC        Overall U of the heating tubes [kW per m2.K]
LambdaAvg       Average latent heat of the distillate [kJ per kg]
Qtotal          Heat transferred in the evaporators [kW]
GOR             Gained output ratio [kg distillate per kg steam]
MS              LPS steam to the first effect [kg per s]
A               Heat-transfer area of each effect [m2]
AFC             Annualised evaporator cost [$ per year]
AOC2            Steam cost of a stand-alone MEE [$ per year]
Distflow        Distillate flow [kg per s]
T_swS           Sea-water feed temperature after the Farm preheat [C]
T_PH_in         Sea-water feed temperature leaving the HEN for the LPS preheater [C]
Q_ext_MEE       Duty of the LPS sea-water preheater [kW]
m_st            LPS to the sea-water preheater [kg per s]
LMTD_MEE        Chen LMTD of the LPS sea-water preheater [K]
A_HX_MEE_PH     Area of the LPS sea-water preheater [m2]
Cst_PH_MEE_HX   Annualised LPS sea-water preheater [$ per year];

Binary Variables
b_PH    LPS sea-water preheater is built;

Integer Variables
NEFF    Number of effects;

Equations
EqSF            Sea-water feed
Massbalance     MEE mass balance
Compbalance     MEE salt balance
EqTVavg         Average distillate temperature
EqDeltaTVac1    Temperature drop per effect
EqUHTFFEAC      Heating-tube U
EqLambdaAvg     Latent heat of the distillate
EqQtotal        Heat to evaporate the distillate
EqQTotal1       Heat transferred in the effects
EqGOR           Gained output ratio
EqMS            Steam needed for the distillate
EqAFC           Annualised evaporator and preheater cost
EqAOC           Steam cost of a stand-alone MEE
EqT_PH          Feed enters the LPS preheater at the Farm outlet temperature when the HEN is absent
EqQ_Ext         Duty of the LPS sea-water preheater
Eq_m_st         LPS to the sea-water preheater
EqQ_PHb         LPS sea-water preheater duty only when it is built
EqLMTD_MEE_HX   Chen LMTD of the LPS sea-water preheater
EqA_MEE_HX      Area of the LPS sea-water preheater
EqCst_PH_MEE_HX Annualised LPS sea-water preheater;

EqSF$act('2')..
    SF =e= SF_d;
Massbalance$act('2')..
    Distflow =e= SF - Brineflow;
Compbalance$act('2')..
    SF*xF =e= Brineflow*xB;
EqTVavg$act('2')..
    TVavg =e= (TSteam + TVfinal)/2;
EqDeltaTVac1$act('2')..
    DeltaTVac =e= (TV1 - TVfinal)/NEFF;
EqUHTFFEAC$act('2')..
    UHTFFEAC =e= U_a + U_b*TVavg;
EqLambdaAvg$act('2')..
    LambdaAvg =e= Lam_a - Lam_b*TVavg;
EqQtotal$act('2')..
    Qtotal =e= Distflow*LambdaAvg;
EqQTotal1$act('2')..
    Qtotal =e= NEFF*UHTFFEAC*A*DeltaTVac;
EqGOR$act('2')..
    GOR =e= NEFF*(GOR_f**NEFF);
EqMS$act('2')..
    MS =e= Distflow/(GOR + epsGOR);
EqAFC$act('2')..
    AFC =e= NEFF*C_evap*(A**n_evap) + Cst_PH_MEE_HX;
EqAOC$act('2')..
    AOC2 =e= steam('sp3','st_p')*(MS + m_st)*3600*OH/1000;

*Feed heating from T_swF to T_swH: Farm warm water (to T_swS; 24, 234), then the HEN (to T_PH_in; 23, 123, 234, 1234),
*then the LPS preheater
EqT_PH$(act('2') and not act('23'))..
    T_PH_in =e= T_swS;
EqQ_Ext$act('2')..
    Q_ext_MEE =e= SF*Cp_sw*(T_swH - T_PH_in);
Eq_m_st$act('2')..
    m_st =e= Q_ext_MEE/H_VapL;
EqQ_PHb$act('2')..
    Q_ext_MEE =l= PH_duty*b_PH;
EqLMTD_MEE_HX$act('2')..
    LMTD_MEE =e= ((T_stPH - T_swH)*(T_stPH - T_PH_in)*((T_stPH - T_swH) + (T_stPH - T_PH_in))/2)**(1/3);
EqA_MEE_HX$act('2')..
    A_HX_MEE_PH =e= Q_ext_MEE/(U_PH_HX*LMTD_MEE);
EqCst_PH_MEE_HX$act('2')..
    Cst_PH_MEE_HX =e= AF_MEE*(CF_MEE*b_PH + ((((A_HX_MEE_PH + epsHE)**AE_MEE) - (epsHE**AE_MEE))*AC_MEE));

Distflow.lo = 28;
Distflow.up = 31;
GOR.lo      = 8;
GOR.up      = 10;

*NEFF bounds keep GOR = NEFF*GOR_f**NEFF in [GOR.lo, GOR.up]: DICOPT cannot cut off values of a general integer variable
NEFF.lo     = 10;
NEFF.up     = 13;

*Start at the smallest NEFF reaching the middle of [GOR.lo, GOR.up]
NEFF.l          = 12;
GOR.l           = NEFF.l*GOR_f**NEFF.l;
SF.l            = SF_d;
Distflow.l      = SF.l*(1 - xF/xB);
Brineflow.l     = SF.l*xF/xB;
TVavg.l         = (TSteam + TVfinal)/2;
DeltaTVac.l     = (TV1 - TVfinal)/NEFF.l;
UHTFFEAC.l      = U_a + U_b*TVavg.l;
LambdaAvg.l     = Lam_a - Lam_b*TVavg.l;
Qtotal.l        = Distflow.l*LambdaAvg.l;
A.l             = Qtotal.l/(NEFF.l*UHTFFEAC.l*DeltaTVac.l);
MS.l            = Distflow.l/(GOR.l + epsGOR);
T_swS.l         = T_swF;
T_PH_in.l       = T_swF;
Q_ext_MEE.l     = SF.l*Cp_sw*(T_swH - T_swF);
m_st.l          = Q_ext_MEE.l/H_VapL;
b_PH.l          = 1;
LMTD_MEE.l      = ((T_stPH - T_swH)*(T_stPH - T_swF)*((T_stPH - T_swH) + (T_stPH - T_swF))/2)**(1/3);
A_HX_MEE_PH.l   = Q_ext_MEE.l/(U_PH_HX*LMTD_MEE.l);
Cst_PH_MEE_HX.l = AF_MEE*(CF_MEE + ((((A_HX_MEE_PH.l + epsHE)**AE_MEE) - (epsHE**AE_MEE))*AC_MEE));
AFC.l           = NEFF.l*C_evap*(A.l**n_evap) + Cst_PH_MEE_HX.l;
AOC2.l          = steam('sp3','st_p')*(MS.l + m_st.l)*3600*OH/1000;

MS.lo       = 0.99*Distflow.lo/(GOR.up + epsGOR);
SF.lo       = 0.99*Distflow.lo/(1 - xF/xB);
A.lo        = 0.99*Distflow.lo*(Lam_a - Lam_b*(TSteam + TVfinal)/2)/((U_a + U_b*(TSteam + TVfinal)/2)*(TV1 - TVfinal));
T_swS.lo    = T_swF;
T_PH_in.lo  = T_swF;
T_PH_in.up  = T_swH;
LMTD_MEE.lo = T_stPH - T_swH;

*==============================================================================================================
*HEAT EXCHANGER NETWORK (HEN)
*==============================================================================================================
Sets
i               Hot streams                                 /1*5/
j               Cold streams                                /1*5/
k               Temperature locations (stage boundaries)    /1*4/
data            Stream data columns                         /TIN, TOUT, H, F, COST, CP, RHO/
hut(i)          Hot utilities
hps(i)          Hot process streams
cps(j)          Cold process streams
cut(j)          Cold utilities
sw(j)           Sea-water feed of the MEE                   /4/
st(k)           Stages
first(k)        First temperature location
last(k)         Last temperature location
hx_st(k)        Heat recovery stages
hut_st(k)       Hot utility stages
cut_st(k)       Cold utility stages
fhps(k)         First temperature location of hps(i)
fcps(k)         First temperature location of cps(j)
first_tlhot(k)  Intervals where hps(i) exist
last_tlhot(k)   Last temperature location of hps(i)
first_tlcold(k) Intervals where cps(j) exist
last_tlcold(k)  Last temperature location of cps(j);

*TIN inlet temperature [C]; TOUT required outlet temperature [C]; H film coefficient [kW per m2.K]; F heat
*capacity flow rate [kW per K]; COST utility cost [$ per kW.year]; CP heat capacity [kJ per kg.K];
*RHO density [kg per m3]
Table   HOTS(i,data)    Hot stream data
            TIN     TOUT    H       F       COST    CP      RHO
        1   257     256     1.8     0.0     5       3.2     21.65
        2   196.60  195.60  1.5     0.0     2       3.6     6.86
        3   154     153     1.2     0.0     1       3.4     2.55
        4   155.00  85.00   0.5     150.0   0       3.1     810
        5   230.00  40.0    0.5     285.0   0       3.3     760;

Table   COLDS(j,data)   Cold stream data
            TIN     TOUT    H       F       COST    CP      RHO
        1   25.00   240.00  0.5     140.0   0       3.2     760
        2   40      180     0.5     70      0       3.3     790
        3   70      100     0.5     120     0       3.5     785
        4   0       0       0.5     0       0       0       1025
        5   5.0     10.00   0.5     0.0     30      4.2     1000;

*Cold stream 4 is the sea-water feed of the MEE, present in Coalitions of the MEE and the HEN
COLDS('4','TIN')    = T_swF;
COLDS('4','TOUT')   = T_swH;
COLDS('4','F')      = Cp_sw*SF_d;
COLDS('4','CP')     = Cp_sw;

Parameters
nhut                Number of hot utilities                                     /3/
ncut                Number of cold utilities                                    /1/
QH(i)               Heat released by hot stream i between TIN and TOUT [kW]
QC(j)               Heat taken by cold stream j between TIN and TOUT [kW]
AF                  Annualisation factor of the HEN exchangers [1 per year]     /0.322/
CF                  Fixed cost per exchanger [$]                                /13000/
AC                  Area cost coefficient of the HEN exchangers [$ per m2]      /1000/
AE                  Area cost exponent of the HEN exchangers                    /0.83/
gamma_var(i,j)      Big-M on the approach temperature when a match is off [K]
EMAT                Exchanger minimum approach temperature [K]                  /1/
epsDT               Offset keeping the Chen LMTD in TERM2 away from zero [K]    /1e-6/
a_hps(i,k)          Intervals in which hps(i) are present
a_cps(j,k)          Intervals in which cps(j) are present
a_hut(i,k)          Intervals in which hot utilities are present
a_cut(j,k)          Intervals in which cold utilities are present
match(i,j,k)        Possible match of hot stream i with cold stream j in stage k
temp_in_hot(i,k)    Location where hot process stream i enters
temp_in_cold(j,k)   Location where cold process stream j enters;

*Subsets of streams and locations (they need nhut and ncut)
st(k)           = yes$(ord(k) < card(k));
first(k)        = yes$(ord(k) eq 1);
last(k)         = yes$(ord(k) eq card(k));
hut(i)          = yes$(ord(i) <= nhut);
cut(j)          = yes$(ord(j) > card(j)-ncut);
hps(i)          = yes$(ord(i) > nhut);
cps(j)          = yes$(ord(j) <= card(j)-ncut and (not sw(j) or act('23')));
hut_st(k)       = yes$(ord(k) = 1);
cut_st(k)       = yes$(ord(k) = card(k)-1);
hx_st(k)        = yes$(ord(k)>=2 and ord(k)<=card(k)-2);
fhps(k)         = yes$(ord(k)=1);
fcps(k)         = yes$(ord(k)=card(k));
first_tlhot(k)  = yes$(ord(k)>=2 and ord(k)<card(k));
last_tlhot(k)   = yes$(ord(k)=card(k));
first_tlcold(k) = yes$(ord(k)<=card(k)-1);
last_tlcold(k)  = yes$(ord(k)=1);

*Duty each process stream must give up or take
QH(i) = HOTS(i,'F')*(HOTS(i,'TIN') - HOTS(i,'TOUT'));
QC(j) = COLDS(j,'F')*(COLDS(j,'TOUT') - COLDS(j,'TIN'));

gamma_var(i,j) = 4000;

*Initialise flags
a_hps(i,k)$(hps(i) and first_tlhot(k))  = 1;
a_cps(j,k)$(cps(j) and first_tlcold(k)) = 1;
a_hut(i,k)                              = 0;
a_cut(j,k)                              = 0;
match(i,j,k)                            = 0;
temp_in_hot(i,k)                        = 0;
temp_in_cold(j,k)                       = 0;

*Assign flag values
a_hut(i,k)$(hut(i) and hut_st(k))       = 1;
a_cut(j,k)$(cut(j) and cut_st(k))       = 1;
match(i,j,k)$(st(k) and ((a_hps(i,k) and a_cps(j,k)$(hps(i) and cps(j))) or (a_cut(j,k)$((hps(i) and cut(j)))) or (a_hut(i,k)$((hut(i) and cps(j)))))) = 1;
temp_in_hot(i,k)$hps(i)                 = fhps(k);
temp_in_cold(j,k)$cps(j)                = fcps(k);

Positive Variables
HENcap      Annualised capital cost of the HEN exchangers [$ per year]
th(i,k)     Temperature of hot stream i as it enters stage k [C]
tc(j,k)     Temperature of cold stream j as it leaves stage k [C]
q(i,j,k)    Heat exchanged between i and j in stage k [kW]
FlowHEN1    Desuperheated HPS used by the HEN as hot utility 1 [kg per s]
FlowHEN2    Desuperheated MPS used by the HEN as hot utility 2 [kg per s]
FlowHEN3    Desuperheated LPS used by the HEN as hot utility 3 [kg per s]
BuyHEN1     HPS the HEN buys in a Coalition with the SCN-CHP [kg per s]
BuyHEN2     MPS the HEN buys in a Coalition with the SCN-CHP [kg per s]
BuyHEN3     LPS the HEN buys in a Coalition with the SCN-CHP [kg per s]
FlowHEN11   Latent heat delivered by hot utility 1 (HPS) [kW]
FlowHEN22   Latent heat delivered by hot utility 2 (MPS) [kW]
FlowHEN33   Latent heat delivered by hot utility 3 (LPS) [kW]
TERM1       Fixed charge of the HEN exchangers [$]
TERM2       Area cost of the HEN exchangers [$]
CUT_Cst     Chilled water bought for the HEN [$ per year]
Q_CUT       Chilled-water duty of the HEN [kW]
F_CUT       Chilled-water flow to the HEN [kg per s]
Q_sw        Heat the HEN gives the sea-water feed of the MEE [kW]
HUT_Cst     Steam bought by a HEN outside a Coalition with the SCN-CHP [$ per year]
HUT_Cst13   Steam the HEN buys in a Coalition with the SCN-CHP [$ per year]
AOC_HEN     Operating cost of a HEN outside a Coalition with the SCN-CHP: bought steam and chilled water [$ per year];

Binary Variables
y(i,j,k) Match of hot stream i with cold stream j in stage k is used;

Variables
dt(i,j,k)   Approach between i and j at location k [K];

Equations
*Temperatures and heat balances
THOT_IN(i,k)                Assignment of hot process stream inlet temperatures
TCOLD_IN(j,k)               Assignment of cold process stream inlet temperatures
TOTAL_HEAT_HOT(i)           Total heat balance of hot process stream hps(i)
TOTAL_HEAT_COLD(j)          Total heat balance of cold process stream cps(j)
STAGE_HEAT_HOT(i,k)         Stage heat balance of hot process stream hps(i)
STAGE_HEAT_COLD(j,k)        Stage heat balance of cold process stream cps(j)
MONOT_HOT(i,k)              Monotonic temperatures of the hot streams
MONOT_COLD(j,k)             Monotonic temperatures of the cold streams
*Logic
LOG_Q_HPS_CPS(i,j,k)        Logical constraint on heat exchanged between hps(i) and cps(j)
LOG_Q_HPS_CUT(i,j,k)        Logical constraint on heat exchanged between hps(i) and cut(j)
LOG_Q_HUT_CPS(i,j,k)        Logical constraint on heat exchanged between hut(i) and cps(j)
LOG_DT_HPS_CPS_HS(i,j,k)    Logical constraint on hot side temperature difference between hps(i) and cps(j)
LOG_DT_HPS_CPS_CS(i,j,k)    Logical constraint on cold side temperature difference between hps(i) and cps(j)
LOG_DT_HPS_CUT_HS(i,j,k)    Logical constraint on hot side temperature difference between hps(i) and cut(j)
LOG_DT_HPS_CUT_CS(i,j,k)    Logical constraint on cold side temperature difference between hps(i) and cut(j)
LOG_DT_HUT_CPS_HS(i,j,k)    Logical constraint on hot side temperature difference between hut(i) and cps(j)
LOG_DT_HUT_CPS_CS(i,j,k)    Logical constraint on cold side temperature difference between hut(i) and cps(j)
*Hot utilities
FlowtoHEN111                Latent heat of hot utility 1
FlowtoHEN222                Latent heat of hot utility 2
FlowtoHEN333                Latent heat of hot utility 3
HEN_HUTconnect1(i)          Hot utility 1 delivers what its matches take
HEN_HUTconnect2(i)          Hot utility 2 delivers what its matches take
HEN_HUTconnect3(i)          Hot utility 3 delivers what its matches take
*Costs
ETERM1                      Fixed charge of the HEN exchangers
ETERM2                      Area cost of the HEN exchangers
EHENcap                     Annualised capital cost of the HEN exchangers
ECUT_Cst                    Chilled-water cost of the HEN
EQ_CUT                      Chilled-water duty of the HEN
EF_CUT                      Chilled-water flow to the HEN
EQ_sw                       Heat the HEN gives the sea-water feed of the MEE
EQ_swT                      Sea-water feed leaves the HEN for the LPS preheater of the MEE
EHUT_Cst                    Steam bought by a HEN outside a Coalition with the SCN-CHP
EHUT_Cst13                  Steam the HEN buys in a Coalition with the SCN-CHP
AOC_HEN_1                   Operating cost of a HEN outside a Coalition with the SCN-CHP: bought steam and chilled water;

*Inlet temperatures; the sea-water feed enters at T_swS (T_swF without the Farm)
THOT_IN(i,k)$(act('3') and hps(i) and temp_in_hot(i,k))..
    th(i,k) =e= HOTS(i,'TIN');
TCOLD_IN(j,k)$(act('3') and cps(j) and temp_in_cold(j,k))..
    tc(j,k) =e= COLDS(j,'TIN') + (T_swS - T_swF)$sw(j);

*Overall heat balance of each stream
TOTAL_HEAT_HOT(i)$(act('3') and hps(i))..
    QH(i) =e= sum((j,k)$(match(i,j,k)), q(i,j,k));
TOTAL_HEAT_COLD(j)$(act('3') and cps(j) and not sw(j))..
    QC(j) =e= sum((i,k)$(match(i,j,k)), q(i,j,k));

*Stage heat balances
STAGE_HEAT_HOT(i,k)$(act('3') and hps(i) and sum(j,match(i,j,k)))..
    HOTS(i,'F')*(th(i,k)-th(i,k+1)) =e= sum(j$match(i,j,k), q(i,j,k));
STAGE_HEAT_COLD(j,k)$(act('3') and cps(j) and sum(i,match(i,j,k)))..
    COLDS(j,'F')*(tc(j,k)-tc(j,k+1)) =e= sum(i$match(i,j,k), q(i,j,k));

*Monotonic temperatures
MONOT_HOT(i,k)$(act('3') and hps(i) and st(k))..
    th(i,k) =g= th(i,k+1);
MONOT_COLD(j,k)$(act('3') and cps(j) and st(k))..
    tc(j,k) =g= tc(j,k+1);

*Heat is exchanged only on a match that is used
LOG_Q_HPS_CPS(i,j,k)$(act('3') and hps(i) and cps(j) and match(i,j,k))..
    q(i,j,k) =l= min(QH(i),QC(j))*y(i,j,k);
LOG_Q_HPS_CUT(i,j,k)$(act('3') and hps(i) and cut(j) and match(i,j,k))..
    q(i,j,k) =l= QH(i)*y(i,j,k);
LOG_Q_HUT_CPS(i,j,k)$(act('3') and hut(i) and cps(j) and match(i,j,k))..
    q(i,j,k) =l= QC(j)*y(i,j,k);

*Approach temperatures, relaxed by gamma_var when the match is not used
LOG_DT_HPS_CPS_HS(i,j,k)$(act('3') and hps(i) and cps(j) and match(i,j,k))..
    dt(i,j,k) =l= th(i,k) - tc(j,k) + gamma_var(i,j)*(1-y(i,j,k));
LOG_DT_HPS_CPS_CS(i,j,k)$(act('3') and hps(i) and cps(j) and match(i,j,k))..
    dt(i,j,k+1) =l= th(i,k+1) - tc(j,k+1) + gamma_var(i,j)*(1-y(i,j,k));
LOG_DT_HPS_CUT_HS(i,j,k)$(act('3') and hps(i) and cut(j) and match(i,j,k))..
    dt(i,j,k) =l= (th(i,k) - COLDS(j,'TOUT')) + gamma_var(i,j)*(1-y(i,j,k));
LOG_DT_HPS_CUT_CS(i,j,k)$(act('3') and hps(i) and cut(j) and match(i,j,k))..
    dt(i,j,k+1) =l= (th(i,k+1) - COLDS(j,'TIN')) + gamma_var(i,j)*(1-y(i,j,k));
LOG_DT_HUT_CPS_HS(i,j,k)$(act('3') and hut(i) and cps(j) and match(i,j,k))..
    dt(i,j,k) =l= (HOTS(i,'TIN') - tc(j,k)) + gamma_var(i,j)*(1-y(i,j,k));
LOG_DT_HUT_CPS_CS(i,j,k)$(act('3') and hut(i) and cps(j) and match(i,j,k))..
    dt(i,j,k+1) =l= (HOTS(i,'TOUT') - tc(j,k+1)) + gamma_var(i,j)*(1-y(i,j,k));

*Condensing hot utilities release latent heat only
FlowtoHEN111$act('3')..
    FlowHEN11 =e= FlowHEN1*H_VapH;
FlowtoHEN222$act('3')..
    FlowHEN22 =e= FlowHEN2*H_VapM;
FlowtoHEN333$act('3')..
    FlowHEN33 =e= FlowHEN3*H_VapL;

HEN_HUTconnect1('1')$act('3')..
    FlowHEN11 =e= sum((j,k),q('1',j,k)$(hut('1') and hut_st(k) and match('1',j,k)));
HEN_HUTconnect2('2')$act('3')..
    FlowHEN22 =e= sum((j,k),q('2',j,k)$(hut('2') and hut_st(k) and match('2',j,k)));
HEN_HUTconnect3('3')$act('3')..
    FlowHEN33 =e= sum((j,k),q('3',j,k)$(hut('3') and hut_st(k) and match('3',j,k)));

*Exchanger cost
ETERM1$act('3')..
    TERM1 =e= CF*sum((i,j,k)$(match(i,j,k)),y(i,j,k));
*Area cost of every possible match (hot process stream - cold process stream, hot process stream - cold utility,
*hot utility - cold process stream), with the Chen approximation of the LMTD
ETERM2$act('3')..
    TERM2 =e= AC*sum((i,j,k)$match(i,j,k),(q(i,j,k)*(1/HOTS(i,'H')+1/COLDS(j,'H'))/((((epsDT**3)+(dt(i,j,k)*dt(i,j,k+1))*((dt(i,j,k)+dt(i,j,k+1))*0.5))**0.3333)+epsDT)+epsDT)**AE);
EHENcap$act('3')..
    HENcap =e= AF*(TERM1 + TERM2);

*Chilled water: cost, duty and flow
ECUT_Cst$act('3')..
    CUT_Cst =e= sum((i,j,k)$(hps(i) and cut(j) and match(i,j,k)),COLDS(j,'COST')*q(i,j,k));
EQ_CUT$act('3')..
    Q_CUT =e= sum((i,j,k)$(hps(i) and cut(j) and match(i,j,k)),q(i,j,k));
EF_CUT$act('3')..
    F_CUT =e= Q_CUT/sum(cut, COLDS(cut,'CP')*(COLDS(cut,'TOUT') - COLDS(cut,'TIN')));

*Sea-water feed (cold stream 4): the HEN supplies any heat up to its duty to T_swH, the LPS preheater the rest
EQ_sw$act('23')..
    Q_sw =e= sum((i,sw,k)$match(i,sw,k), q(i,sw,k));
EQ_swT$act('23')..
    T_PH_in =e= T_swS + Q_sw/(SF*Cp_sw);
Q_sw.fx$(not act('23')) = 0;

*Steam bought by the HEN
EHUT_Cst$act('3')..
    HUT_Cst =e= (((FlowHEN1*steam('sp1','st_p'))+(FlowHEN2*steam('sp2','st_p'))+(FlowHEN3*steam('sp3','st_p')))*3600*OH/1000);
EHUT_Cst13$act('13')..
    HUT_Cst13 =e= (BuyHEN1*steam('sp1','st_p') + BuyHEN2*steam('sp2','st_p') + BuyHEN3*steam('sp3','st_p'))*3600*OH/1000;
AOC_HEN_1$act('3')..
    AOC_HEN =e= (((FlowHEN1*steam('sp1','st_p'))+(FlowHEN2*steam('sp2','st_p'))+(FlowHEN3*steam('sp3','st_p')))*3600*OH/1000) + CUT_Cst;

*Approach temperatures start at the inlet difference
dt.l(i,j,k)$match(i,j,k)    = HOTS(i,'TIN')-COLDS(j,'TIN');
dt.l(i,j,k+1)$match(i,j,k)  = HOTS(i,'TIN')-COLDS(j,'TIN');
dt.lo(i,j,k)$match(i,j,k)   = EMAT;
dt.lo(i,j,k+1)$match(i,j,k) = EMAT;
dt.up(i,j,k)$match(i,j,k)   = 400;
dt.up(i,j,k+1)$match(i,j,k) = 400;

*Heat loads start at, and are bounded by, the smaller of the two duties
q.l(i,j,k)$(hps(i) and cps(j) and match(i,j,k))     = min(QH(i),QC(j));
q.l(i,j,k)$(hps(i) and cut(j) and match(i,j,k))     = QH(i);
q.l(i,j,k)$(hut(i) and cps(j) and match(i,j,k))     = QC(j);
q.up(i,j,k)$(hps(i) and cps(j) and match(i,j,k))    = min(QH(i),QC(j));
q.up(i,j,k)$(hps(i) and cut(j) and match(i,j,k))    = QH(i);
q.up(i,j,k)$(hut(i) and cps(j) and match(i,j,k))    = QC(j);
q.l(i,sw,k)$match(i,sw,k)                           = 0;

*Initialisations and bounds for intermediate temperatures
th.l(i,k)$(first(k))                = HOTS(i,'TIN');
tc.l(j,k)$(last(k))                 = COLDS(j,'TIN');
th.lo(i,k)$(last(k))                = HOTS(i,'TOUT');
th.up(i,k)$(first(k))               = HOTS(i,'TIN');
tc.lo(j,k)$(last(k))                = COLDS(j,'TIN');
tc.up(j,k)$(first(k) and cps(j))    = COLDS(j,'TOUT');

*Upper bounds on the HEN steam flows, far above any solution flow
FlowHEN1.up = 999;
FlowHEN2.up = 3000;
FlowHEN3.up = 1999;

*==============================================================================================================
*STEAM LINKS BETWEEN THE SCN-CHP, MEE AND HEN
*==============================================================================================================
*With the SCN-CHP the HEN draws desuperheated steam from it and may buy more (EHUT_Cst13); without it the HEN buys all its
*steam (EHUT_Cst)
Equations
FlowtoHEN1  The HEN takes all the desuperheated HPS and any HPS it buys in a Coalition with the SCN-CHP
FlowtoHEN2  HEN MPS within the desuperheated MPS and the MPS it buys in a Coalition with the SCN-CHP
FlowtoHEN3  HEN LPS within the desuperheated LPS and the LPS it buys in a Coalition with the SCN-CHP
FlowtoHEN3b LPS covers MEE steam and preheater and HEN LPS not bought in a Coalition of the SCN-CHP with the MEE and HEN
FlowtoHEN3c LPS covers the MEE steam and preheater in a Coalition of the SCN-CHP with the MEE;

FlowtoHEN1$act('13')..
    FlowHEN1 =e= HPSd + BuyHEN1;
FlowtoHEN2$act('13')..
    MPSd + BuyHEN2 =g= FlowHEN2;
FlowtoHEN3$act('13')..
    LPSd + BuyHEN3 =g= FlowHEN3;

*LPS covers the MEE steam and preheater (3c) and the HEN LPS that is not bought (3b)
FlowtoHEN3b$act('123')..
    LPSd - MS - m_st + BuyHEN3 =g= FlowHEN3;
FlowtoHEN3c$act('12')..
    LPSd - MS - m_st =g= 0;

*The HEN receives HPS from the SCN-CHP only in a Coalition with it
InletflowHEN.fx$(not act('13')) = 0;

*==============================================================================================================
*CRYPTO-MINING FARM
*==============================================================================================================
*Alone: grid power and cooling water, heat dumped.
*With the SCN-CHP: CHP power above D_ind (ESCN_CHP_Pw), warm water preheats the boiler feed. With the MEE but not the
*SCN-CHP: warm water preheats the MEE sea-water feed. No link to the HEN.

Parameters
hashP           'Mean hashprice from Blockchain.com daily data [$ per PH/s per day]'            /36.31/
c_MF            Mean Megaflex active energy charge [c per kWh]                                  /182.00/
c_lev           Per-kWh charges on all consumption [c per kWh]                                  /35.03/
cr_netfix       Megaflex capacity charges [R per kVA per month]                                 /88.84/
cr_pf           Farm power factor                                                               /0.95/
cr_eff          Miner efficiency [J per TH]                                                     /12/
cr_asic         'ASIC (mining chip) price [$ per TH/s]'                                         /14.59/
cr_infra        Farm infrastructure cost [$ per kW]                                             /300/
cr_PUE          Power usage effectiveness                                                       /1.05/
cr_pool         Mining pool fee                                                                 /0.02/
cr_avail        Miner availability                                                              /0.97/
cr_CapMin       Smallest Farm when built [kW]                                                   /599/
cr_lifeA        ASIC replacement interval [year]                                                /3/
cr_lifeI        Infrastructure life [year]                                                      /10/
cr_rate         Discount rate for annualising [1 per year]                                      /0.10/
cr_OM           Fixed O&M as a fraction of capital [1 per year]                                 /0.03/
cr_kBTC         BTC price multiplier (--BTCMULT)                                                /%BTCMULT%/
T_cr            Farm cooling-water outlet [C]                                                   /60/
dT_cr           Approach in the Farm's exchangers [K]                                           /5/
r_m             Mining revenue per kWh of Farm electricity [$ per kWh]
p_buy           Grid price paid by a Farm without the SCN-CHP [$ per kWh]
cr_cA           ASIC capital per kW of Farm [$ per kW]
cr_ann          Annualised capital and fixed O&M per kW of Farm [$ per kW per year]
cr_fix          Megaflex capacity charges per kW of grid-supplied Farm [$ per kW per year]
cr_CapMax       Largest Farm: the two turbine maxima [kW]
QcrMax          Heat the largest Farm sends to its cooling water [kW]
U_cr            U of the Farm's exchangers [kW per m2.K]
T_fw            Cold boiler feed temperature [C];

r_m             = cr_kBTC*(hashP/1000)*(1 - cr_pool)/(0.024*cr_eff*cr_PUE);
p_buy           = (c_MF + c_lev)/(100*FX);
cr_cA           = cr_asic*1000/(cr_eff*cr_PUE);
cr_ann          = cr_cA*cr_rate*(1 + cr_rate)**cr_lifeA/((1 + cr_rate)**cr_lifeA - 1) + cr_infra*cr_rate*(1 + cr_rate)**cr_lifeI/((1 + cr_rate)**cr_lifeI - 1) + cr_OM*(cr_cA + cr_infra);
cr_fix          = 12*cr_netfix/(cr_pf*FX);
cr_CapMax       = sum(T, MaxG(T));
QcrMax          = cr_CapMax/cr_PUE;

U_cr            = U_st;
T_fw            = Streamproperties('ws1','sTmp1');

HPSTmax         = smin(s, sum(sp, capacity(sp,s)*BE*NC(sp)/(OH*DS(s))))/(h_HPS - h_fw - CP_s*(Streamproperties('ws2','sTmp2') - Streamproperties('ws2','sTmp1')) - CP_s*(T_cr - dT_cr - T_fw));

Positive Variables
CR_Cap          Farm electrical capacity including cooling [kW]
CR_Pgr          Grid power bought by the Farm [kW]
CR_Qdmp         Farm heat leaving with the discharged cooling water [kW]
CR_Fcw          Farm cooling water [kg per s]
CR_Fw           Warm water to the boiler-feed exchanger [kg per s]
A_crB           Area of the Farm-to-boiler-feed exchanger [m2]
CR_capc         Annualised Farm capital and fixed O&M [$ per year]
CR_rev          Mining revenue [$ per year]
CR_grid         Grid energy bought by the Farm [$ per year]
CR_HXB          Annualised Farm-to-boiler-feed exchanger [$ per year]
Q_crS           Farm heat added to the sea-water feed of the MEE [kW]
A_crS           Area of the Farm-to-sea-water exchanger [m2]
T_crS           Farm warm water leaving the Farm-to-sea-water exchanger [C]
LMTD_crS        Chen LMTD of the Farm-to-sea-water exchanger [K]
CR_HXS          Annualised Farm-to-sea-water exchanger [$ per year]
CR_cw           Farm cooling-water cost [$ per year];

Binary Variables
b_cr            Farm is built
b_crB           Farm-to-boiler-feed exchanger is built
b_crS           Farm-to-sea-water exchanger is built;

Equations
CR_CapL         Farm capacity at least cr_CapMin when built
CR_CapU         Farm capacity zero when not built
CR_Avl          Farm runs at its available capacity
CR_Heat         Farm heat: the preheat and the rest leaves with the cooling water
CR_cwE          Farm cooling water
CR_cwcE         Farm cooling-water cost
CR_QBT          Boiler-feed preheat within what the warm water can heat the cold feed to
CR_QBh          Boiler-feed preheat within what the warm water can give before it is dT_cr above the cold feed
CR_QBb          Boiler-feed preheat only when its exchanger is built
CR_AB           Farm-to-boiler-feed exchanger sized for the preheat duty
CR_HXBE         Annualised Farm-to-boiler-feed exchanger
CR_FwE          Warm water to the boiler-feed exchanger
CR_QST          Sea-water preheat within what the warm water can heat the feed to
CR_TswS         Sea-water feed temperature after the Farm preheat
CR_TcrS         Farm warm water temperature after the sea-water preheat
CR_LMS          Chen LMTD of the Farm-to-sea-water exchanger
CR_QSb          Sea-water preheat only when its exchanger is built
CR_AS           Farm-to-sea-water exchanger sized for the preheat duty
CR_HXSE         Annualised Farm-to-sea-water exchanger
CR_capE         Annualised Farm capital and fixed O&M
CR_revE         Mining revenue
CR_gridE        Grid energy bought by the Farm;

CR_CapL$act('4')..
    CR_Cap =g= cr_CapMin*b_cr;
CR_CapU$act('4')..
    CR_Cap =l= cr_CapMax*b_cr;

CR_Avl$act('4')..
    CR_Pco + CR_Pgr =e= cr_avail*CR_Cap;

CR_Heat$act('4')..
    CR_Qdmp =e= (CR_Pco + CR_Pgr)/cr_PUE - Q_crB - Q_crS;

CR_cwE$act('4')..
    CR_Fcw*Cp_wt*(T_cr - Tw_in) =e= (OH*CR_Pco + HY*CR_Pgr)/(OH*cr_PUE);
CR_cwcE$act('4')..
    CR_cw =e= CR_Fcw*Streamproperties('ws6','sCst')*3.6*OH;

CR_QBT$act('14')..
    Q_crB =l= HPST*CP_s*(T_cr - dT_cr - T_fw);
CR_QBh$act('14')..
    Q_crB =l= (CR_Pco + CR_Pgr)/cr_PUE*(T_cr - dT_cr - T_fw)/(T_cr - Tw_in);
CR_QBb$act('14')..
    Q_crB =l= QcrMax*b_crB;

CR_AB$act('14')..
    A_crB =e= Q_crB/(U_cr*dT_cr);
CR_HXBE$act('14')..
    CR_HXB =e= AF_cnd*(CF_cnd*b_crB + ((((A_crB + epsHE)**AE_cnd) - (epsHE**AE_cnd))*AC_cnd));

CR_FwE$act('14')..
    CR_Fw =e= Q_crB/(Cp_wt*(T_cr - dT_cr - T_fw));

*Warm water heats the MEE feed from T_swF to T_swS ahead of the HEN and LPS preheater (duty cut kW for kW). The cooling
*water passes the exchanger in counterflow and leaves at T_crS, at least dT_cr above the feed (T_crS.lo)
CR_QST$(act('24') and not act('1'))..
    Q_crS =l= SF*Cp_sw*(T_cr - dT_cr - T_swF);
CR_TswS$(act('24') and not act('1'))..
    T_swS =e= T_swF + Q_crS/(SF*Cp_sw);
CR_TcrS$(act('24') and not act('1'))..
    Q_crS*(T_cr - Tw_in) =e= (CR_Pco + CR_Pgr)/cr_PUE*(T_cr - T_crS);
CR_QSb$(act('24') and not act('1'))..
    Q_crS =l= QcrMax*b_crS;

CR_LMS$(act('24') and not act('1'))..
    LMTD_crS =e= ((T_cr - T_swS)*(T_crS - T_swF)*((T_cr - T_swS) + (T_crS - T_swF))/2)**(1/3);
CR_AS$(act('24') and not act('1'))..
    A_crS =e= Q_crS/(U_cr*LMTD_crS);
CR_HXSE$(act('24') and not act('1'))..
    CR_HXS =e= AF_cnd*(CF_cnd*b_crS + ((((A_crS + epsHE)**AE_cnd) - (epsHE**AE_cnd))*AC_cnd));

CR_capE$act('4')..
    CR_capc =e= cr_ann*CR_Cap;
CR_revE$act('4')..
    CR_rev =e= r_m*(OH*CR_Pco + HY*CR_Pgr);
CR_gridE$act('4')..
    CR_grid =e= HY*p_buy*CR_Pgr;

CR_Cap.up                   = cr_CapMax;
CR_Fw.up                    = QcrMax/(Cp_wt*(T_cr - dT_cr - T_fw));
T_crS.lo                    = T_swF + dT_cr;
T_crS.up                    = T_cr;
LMTD_crS.lo                 = dT_cr;

CR_Cap.l                    = cr_CapMin;
b_cr.l                      = 1;
Q_crB.l                     = 1000;
A_crB.l                     = 1000/(U_cr*dT_cr);
CR_Fw.l                     = 1000/(Cp_wt*(T_cr - dT_cr - T_fw));
b_crB.l                     = 1;
Q_crS.l                     = 300;
T_crS.l                     = max(T_crS.lo, T_cr - Q_crS.l*(T_cr - Tw_in)/(cr_avail*max(cr_CapMin, 1)/cr_PUE));
LMTD_crS.l                  = ((T_cr - T_swF)*(T_crS.l - T_swF)*((T_cr - T_swF) + (T_crS.l - T_swF))/2)**(1/3);
A_crS.l                     = Q_crS.l/(U_cr*LMTD_crS.l);
b_crS.l                     = 1;

CR_Pco.fx$(not act('14'))   = 0;
Q_crB.fx$(not act('14'))    = 0;
Q_crS.fx$(not (act('24') and not act('1'))) = 0;
T_swS.fx$(not (act('24') and not act('1'))) = T_swF;
CR_Pgr.fx$act('14')         = 0;

*==============================================================================================================
*SCN-CHP EcO IN EACH COALITION
*==============================================================================================================
Positive Variables
*Stand-alone SCN-CHP
Cl_Wt(Cndr) Cooling water of each header condenser of the stand-alone SCN-CHP [kg per s]
Wt_Total    Total cooling water of the stand-alone SCN-CHP [kg per s]
Wt_cost     Cooling-water cost of the stand-alone SCN-CHP [$ per year]
A_CndL      LPS condenser area of the stand-alone SCN-CHP [m2]
A_CndM      MPS condenser area of the stand-alone SCN-CHP [m2]
A_CndH      HPS condenser area of the stand-alone SCN-CHP [m2]
Cnd_Cst     Annualised header-condenser cost of the stand-alone SCN-CHP [$ per year]
*Coalition 12
Cl_wtLa     Cooling water of the LPS condenser in Coalition 12 [kg per s]
A_CndLa     LPS condenser area in Coalition 12 [m2]
Cnd_csta    Annualised header-condenser cost in Coalition 12 [$ per year]
wt_totalA   Total cooling water in Coalition 12 [kg per s]
wt_costA    Cooling-water cost in Coalition 12 [$ per year]
*Coalition 13 (the MPS and HPS condensers also serve Coalition 123)
Cl_wtLb     Cooling water of the LPS condenser in Coalition 13 [kg per s]
Cl_WtMb     Cooling water of the MPS condenser in Coalitions 13 and 123 [kg per s]
Cl_WtHb     Cooling water of the HPS condenser in Coalitions 13 and 123 [kg per s]
A_CndLb     LPS condenser area in Coalition 13 [m2]
A_CndMb     MPS condenser area in Coalitions 13 and 123 [m2]
A_CndHb     HPS condenser area in Coalitions 13 and 123 [m2]
Cnd_cstb    Annualised header-condenser cost in Coalition 13 [$ per year]
wt_totalB   Total cooling water in Coalition 13 [kg per s]
wt_costB    Cooling-water cost in Coalition 13 [$ per year]
*Coalition 123
Cl_WtLc     Cooling water of the LPS condenser in Coalition 123 [kg per s]
A_CndLc     LPS condenser area in Coalition 123 [m2]
Cnd_cstc    Annualised header-condenser cost in Coalition 123 [$ per year]
wt_totalc   Total cooling water in Coalition 123 [kg per s]
wt_costC    Cooling-water cost in Coalition 123 [$ per year];

Variables
SCN_CHP_EcOA        EcO of the stand-alone SCN-CHP [1e5 $ per year]
SCN_CHP_EcOA12      SCN-CHP EcO in Coalition 12 with the MEE [1e5 $ per year]
SCN_CHP_EcOA13      SCN-CHP EcO in Coalition 13 with the HEN [1e5 $ per year]
SCN_CHP_EcOA123     SCN-CHP EcO in Coalition 123 [1e5 $ per year]
SCN_CHP_EcOA14      SCN-CHP EcO in Coalition 14 with the Farm [1e5 $ per year]
SCN_CHP_EcOA124     SCN-CHP EcO in Coalition 124 with the MEE and the Farm [1e5 $ per year]
SCN_CHP_EcOA134     SCN-CHP EcO in Coalition 134 with the HEN and the Farm [1e5 $ per year]
SCN_CHP_EcOA1234    SCN-CHP EcO in Coalition 1234 [1e5 $ per year];

Equations
*Stand-alone SCN-CHP
EWt_L               Cooling water of the LPS condenser of the stand-alone SCN-CHP
EWt_M               Cooling water of the MPS condenser of the stand-alone SCN-CHP
EWt_H               Cooling water of the HPS condenser of the stand-alone SCN-CHP
EWt_Total           Total cooling water of the stand-alone SCN-CHP
EWt_Cst             Cooling-water cost of the stand-alone SCN-CHP
EA_CndL             LPS condenser area of the stand-alone SCN-CHP
EA_CndM             MPS condenser area of the stand-alone SCN-CHP
EA_CndH             HPS condenser area of the stand-alone SCN-CHP
ECnd_cst            Annualised header-condenser cost of the stand-alone SCN-CHP
ESCN_CHP_EcOA       EcO of the stand-alone SCN-CHP
*Coalition 12
EWt_La              Cooling water of the LPS condenser in Coalition 12
EA_CndLa            LPS condenser area in Coalition 12
ECnd_csta           Annualised header-condenser cost in Coalition 12
Ewt_totalA          Total cooling water in Coalition 12
EWt_costA           Cooling-water cost in Coalition 12
ESCN_CHP_EcOA12     SCN-CHP EcO in Coalition 12
*Coalition 13
EWt_Lb              Cooling water of the LPS condenser in Coalition 13
EWt_Mb              Cooling water of the MPS condenser in Coalitions 13 and 123
EWt_Hb              Cooling water of the HPS condenser in Coalitions 13 and 123
EA_CndLb            LPS condenser area in Coalition 13
EA_CndMb            MPS condenser area in Coalitions 13 and 123
EA_CndHb            HPS condenser area in Coalitions 13 and 123
ECnd_cstb           Annualised header-condenser cost in Coalition 13
Ewt_totalB          Total cooling water in Coalition 13
EWt_costB           Cooling-water cost in Coalition 13
ESCN_CHP_EcOA13     SCN-CHP EcO in Coalition 13
*Coalition 123
EWt_Lc              Cooling water of the LPS condenser in Coalition 123
EA_CndLc            LPS condenser area in Coalition 123
ECnd_cstc           Annualised header-condenser cost in Coalition 123
Ewt_totalc          Total cooling water in Coalition 123
EWt_costC           Cooling-water cost in Coalition 123
ESCN_CHP_EcOA123    SCN-CHP EcO in Coalition 123
*Coalitions with the Farm
ESCN_CHP_EcOA14     SCN-CHP EcO in Coalition 14
ESCN_CHP_EcOA124    SCN-CHP EcO in Coalition 124
ESCN_CHP_EcOA134    SCN-CHP EcO in Coalition 134
ESCN_CHP_EcOA1234   SCN-CHP EcO in Coalition 1234;

*Stand-alone SCN-CHP
EWt_L$act('1')..
    Cl_Wt('cndL') =e= LPSd*cw_Cnd('cndL');
EWt_M$act('1')..
    Cl_Wt('cndM') =e= MPSd*cw_Cnd('cndM');
EWt_H$act('1')..
    Cl_Wt('cndH') =e= HPSd*cw_Cnd('cndH');
EWt_Total$act('1')..
    Wt_Total =e= sum((Cndr), Cl_Wt(Cndr)) + Cl_WtC;
EWt_Cst$act('1')..
    Wt_cost =e= Wt_Total * (Streamproperties('ws6','sCst'))*3.6*OH;
EA_CndL$act('1')..
    A_CndL =e= Cl_Wt('cndL')*kA_Cnd('cndL');
EA_CndM$act('1')..
    A_CndM =e= Cl_Wt('cndM')*kA_Cnd('cndM');
EA_CndH$act('1')..
    A_CndH =e= Cl_Wt('cndH')*kA_Cnd('cndH');

ECnd_cst$act('1')..
    Cnd_Cst =e= AF_cnd*(CF_cnd + ((((A_CndL + A_CndM + A_CndH + epsHE)**AE_cnd) - (epsHE**AE_cnd))*AC_cnd));
ESCN_CHP_EcOA$act('1')..
    SCN_CHP_EcOA =e= (SCN_CHP_com + Wt_cost + Cnd_Cst)/EcOunit;

*Coalition 12: only the LPS left after the MEE share is condensed
EWt_La$act('12')..
    Cl_wtLa =e= (LPSd - MS - m_st)*cw_Cnd('cndL');
EA_CndLa$act('12')..
    A_CndLa =e= Cl_wtLa*kA_Cnd('cndL');
ECnd_csta$act('12')..
    Cnd_csta =e= AF_cnd*(CF_cnd + ((((A_CndLa + A_CndM + A_CndH + epsHE)**AE_cnd) - (epsHE**AE_cnd))*AC_cnd));
Ewt_totalA$act('12')..
    wt_totalA =e= Cl_Wt('cndM')+Cl_Wt('cndH') + Cl_wtLa + Cl_WtC;
EWt_costA$act('12')..
    wt_costA =e= (wt_totalA) * (Streamproperties('ws6','sCst'))*3.6*OH;
ESCN_CHP_EcOA12$act('12')..
    SCN_CHP_EcOA12 =e= (SCN_CHP_com + wt_costA + Cnd_csta)/EcOunit;

*Coalition 13: the condensers handle the steam left after the HEN share (EWt_Lb, EWt_Mb, EWt_Hb); the MPS and HPS
*condensers are sized on their own flows (Cl_WtMb, Cl_WtHb)
EWt_Lb$act('13')..
    Cl_wtLb =e= (LPSd - FlowHEN3 + BuyHEN3)*cw_Cnd('cndL');
EWt_Mb$act('13')..
    Cl_WtMb =e= (MPSd - FlowHEN2 + BuyHEN2)*cw_Cnd('cndM');
EWt_Hb$act('13')..
    Cl_WtHb =e= (HPSd - FlowHEN1 + BuyHEN1)*cw_Cnd('cndH');
EA_CndLb$act('13')..
    A_CndLb =e= Cl_wtLb*kA_Cnd('cndL');
EA_CndMb$act('13')..
    A_CndMb =e= Cl_WtMb*kA_Cnd('cndM');
EA_CndHb$act('13')..
    A_CndHb =e= Cl_WtHb*kA_Cnd('cndH');
ECnd_cstb$act('13')..
    Cnd_cstb =e= AF_cnd*(CF_cnd + ((((A_CndLb + A_CndMb + A_CndHb + epsHE)**AE_cnd) - (epsHE**AE_cnd))*AC_cnd));
Ewt_totalB$act('13')..
    wt_totalB =e= Cl_WtHb + Cl_WtMb + Cl_wtLb + Cl_WtC;
EWt_costB$act('13')..
    wt_costB =e= (wt_totalB) * (Streamproperties('ws6','sCst'))*3.6*OH;
ESCN_CHP_EcOA13$act('13')..
    SCN_CHP_EcOA13 =e= (SCN_CHP_com + wt_costB + Cnd_cstb)/EcOunit;

*Coalition 123
EWt_Lc$act('123')..
    Cl_WtLc =e= (LPSd - FlowHEN3 + BuyHEN3 - MS - m_st)*cw_Cnd('cndL');
EA_CndLc$act('123')..
    A_CndLc =e= Cl_WtLc*kA_Cnd('cndL');
ECnd_cstc$act('123')..
    Cnd_cstc =e= AF_cnd*(CF_cnd + ((((A_CndLc + A_CndMb + A_CndHb + epsHE)**AE_cnd) - (epsHE**AE_cnd))*AC_cnd));
Ewt_totalc$act('123')..
    wt_totalc =e= Cl_WtHb + Cl_WtMb + Cl_WtLc + Cl_WtC;
EWt_costC$act('123')..
    wt_costC =e= (wt_totalc) * (Streamproperties('ws6','sCst'))*3.6*OH;
ESCN_CHP_EcOA123$act('123')..
    SCN_CHP_EcOA123 =e= (SCN_CHP_com + wt_costC + Cnd_cstc)/EcOunit;

*With the Farm: the SCN-CHP EcO has the terms of the same Coalition without it
ESCN_CHP_EcOA14$act('14')..
    SCN_CHP_EcOA14 =e= (SCN_CHP_com + Wt_cost + Cnd_Cst)/EcOunit;
ESCN_CHP_EcOA124$act('124')..
    SCN_CHP_EcOA124 =e= (SCN_CHP_com + wt_costA + Cnd_csta)/EcOunit;
ESCN_CHP_EcOA134$act('134')..
    SCN_CHP_EcOA134 =e= (SCN_CHP_com + wt_costB + Cnd_cstb)/EcOunit;
ESCN_CHP_EcOA1234$act('1234')..
    SCN_CHP_EcOA1234 =e= (SCN_CHP_com + wt_costC + Cnd_cstc)/EcOunit;

*==============================================================================================================
*MEE EcO IN EACH COALITION
*==============================================================================================================
Positive Variables
MEE_EcO2    EcO of the stand-alone MEE [1e5 $ per year]
MEE_EcO12   MEE EcO in Coalition 12 [1e5 $ per year]
MEE_EcO23   MEE EcO in Coalition 23 [1e5 $ per year]
MEE_EcO123  MEE EcO in Coalition 123 [1e5 $ per year]
MEE_EcO24   MEE EcO in Coalition 24 with the Farm [1e5 $ per year]
MEE_EcO124  MEE EcO in Coalition 124 [1e5 $ per year]
MEE_EcO234  MEE EcO in Coalition 234 [1e5 $ per year]
MEE_EcO1234 MEE EcO in Coalition 1234 [1e5 $ per year];

Equations
EMEE_EcO2       EcO of the stand-alone MEE
EMEE_EcO12      MEE EcO in Coalition 12
EMEE_EcO23      MEE EcO in Coalition 23
EMEE_EcO123     MEE EcO in Coalition 123
EMEE_EcO24      MEE EcO in Coalition 24
EMEE_EcO124     MEE EcO in Coalition 124
EMEE_EcO234     MEE EcO in Coalition 234
EMEE_EcO1234    MEE EcO in Coalition 1234;

*Without the SCN-CHP the MEE buys its LPS (AOC2), less what the Farm (24, 234) and HEN (23, 234) preheat; with it the LPS
*comes from the SCN-CHP (steam links) and the MEE pays only AFC
EMEE_EcO2$act('2')..
    MEE_EcO2 =e= (AFC + AOC2)/EcOunit;
EMEE_EcO12$act('12')..
    MEE_EcO12 =e= AFC/EcOunit;
EMEE_EcO23$act('23')..
    MEE_EcO23 =e= (AFC + AOC2)/EcOunit;
EMEE_EcO123$act('123')..
    MEE_EcO123 =e= (AFC)/EcOunit;

EMEE_EcO24$act('24')..
    MEE_EcO24 =e= (AFC + AOC2)/EcOunit;
EMEE_EcO124$act('124')..
    MEE_EcO124 =e= AFC/EcOunit;
EMEE_EcO234$act('234')..
    MEE_EcO234 =e= (AFC + AOC2)/EcOunit;
EMEE_EcO1234$act('1234')..
    MEE_EcO1234 =e= AFC/EcOunit;

*==============================================================================================================
*HEN EcO IN EACH COALITION
*==============================================================================================================
Positive Variables
HEN_EcO     EcO of the stand-alone HEN [1e5 $ per year]
HEN_EcO13   HEN EcO in Coalition 13 [1e5 $ per year]
HEN_EcO23   HEN EcO in Coalition 23 [1e5 $ per year]
HEN_EcO123  HEN EcO in Coalition 123 [1e5 $ per year]
HEN_EcO34   HEN EcO in Coalition 34 with the Farm [1e5 $ per year]
HEN_EcO134  HEN EcO in Coalition 134 [1e5 $ per year]
HEN_EcO234  HEN EcO in Coalition 234 [1e5 $ per year]
HEN_EcO1234 HEN EcO in Coalition 1234 [1e5 $ per year];

Equations
EHENEcO3    EcO of the stand-alone HEN
EHENEcO13   HEN EcO in Coalition 13
EHENEcO23   HEN EcO in Coalition 23
EHENEcO123  HEN EcO in Coalition 123
EHENEcO34   HEN EcO in Coalition 34
EHENEcO134  HEN EcO in Coalition 134
EHENEcO234  HEN EcO in Coalition 234
EHENEcO1234 HEN EcO in Coalition 1234;

EHENEcO3$act('3')..
    HEN_EcO =e= (HENcap + AOC_HEN)/EcOunit;
*Chilled water is charged in every Coalition
EHENEcO13$act('13')..
    HEN_EcO13 =e= (HENcap + CUT_Cst + HUT_Cst13)/EcOunit;
EHENEcO23$act('23')..
    HEN_EcO23 =e= (HENcap + AOC_HEN)/EcOunit;
EHENEcO123$act('123')..
    HEN_EcO123 =e= (HENcap + CUT_Cst + HUT_Cst13)/EcOunit;

*The HEN EcO with the Farm equals that of the Coalition without it
EHENEcO34$act('34')..
    HEN_EcO34 =e= (HENcap + AOC_HEN)/EcOunit;
EHENEcO134$act('134')..
    HEN_EcO134 =e= (HENcap + CUT_Cst + HUT_Cst13)/EcOunit;
EHENEcO234$act('234')..
    HEN_EcO234 =e= (HENcap + AOC_HEN)/EcOunit;
EHENEcO1234$act('1234')..
    HEN_EcO1234 =e= (HENcap + CUT_Cst + HUT_Cst13)/EcOunit;

*==============================================================================================================
*CRYPTO-FARM EcO IN EACH COALITION
*==============================================================================================================
*Negative is a profit
Variables
CR_EcO4     EcO of the stand-alone Farm [1e5 $ per year]
CR_EcO24    Farm EcO in Coalition 24 [1e5 $ per year]
CR_EcO34    Farm EcO in Coalition 34 [1e5 $ per year]
CR_EcO234   Farm EcO in Coalition 234 [1e5 $ per year]
CR_EcO14    Farm EcO in Coalition 14 [1e5 $ per year]
CR_EcO124   Farm EcO in Coalition 124 [1e5 $ per year]
CR_EcO134   Farm EcO in Coalition 134 [1e5 $ per year]
CR_EcO1234  Farm EcO in Coalition 1234 [1e5 $ per year];

Equations
ECR_EcO4    EcO of the stand-alone Farm
ECR_EcO24   Farm EcO in Coalition 24
ECR_EcO34   Farm EcO in Coalition 34
ECR_EcO234  Farm EcO in Coalition 234
ECR_EcO14   Farm EcO in Coalition 14
ECR_EcO124  Farm EcO in Coalition 124
ECR_EcO134  Farm EcO in Coalition 134
ECR_EcO1234 Farm EcO in Coalition 1234;

*Without the SCN-CHP: grid power and Megaflex capacity charges. Exchanger to the sea-water feed with the MEE
*(24, 234), to the boiler feed with the SCN-CHP. The Farm exchanges nothing with the HEN: 34 costs it what 4 does; 124, 134
*and 1234 what 14 does
ECR_EcO4$act('4')..
    CR_EcO4 =e= (CR_capc + cr_fix*CR_Cap + CR_grid + CR_cw - CR_rev)/EcOunit;
ECR_EcO24$act('24')..
    CR_EcO24 =e= (CR_capc + cr_fix*CR_Cap + CR_grid + CR_HXS + CR_cw - CR_rev)/EcOunit;
ECR_EcO34$act('34')..
    CR_EcO34 =e= (CR_capc + cr_fix*CR_Cap + CR_grid + CR_cw - CR_rev)/EcOunit;
ECR_EcO234$act('234')..
    CR_EcO234 =e= (CR_capc + cr_fix*CR_Cap + CR_grid + CR_HXS + CR_cw - CR_rev)/EcOunit;
ECR_EcO14$act('14')..
    CR_EcO14 =e= (CR_capc + CR_HXB + CR_cw - CR_rev)/EcOunit;
ECR_EcO124$act('124')..
    CR_EcO124 =e= (CR_capc + CR_HXB + CR_cw - CR_rev)/EcOunit;
ECR_EcO134$act('134')..
    CR_EcO134 =e= (CR_capc + CR_HXB + CR_cw - CR_rev)/EcOunit;
ECR_EcO1234$act('1234')..
    CR_EcO1234 =e= (CR_capc + CR_HXB + CR_cw - CR_rev)/EcOunit;

*==============================================================================================================
*EnO OF EACH PLAYER IN EACH COALITION
*==============================================================================================================
*EnO: SCN-CHP fuel and freight CO2 plus cooling-water CO2e; for the others the CO2e of the steam, grid power and cooling
*or chilled water they buy (steam and power from the SCN-CHP count in its EnO). kg per s x 3600 x OH x 1e-6 is kt per year
Positive Variables
*SCN-CHP
SCN_CHP_EnO     EnO of the stand-alone SCN-CHP [kt CO2e per year]
SCN_CHP_EnO12   SCN-CHP EnO in Coalition 12 with the MEE [kt CO2e per year]
SCN_CHP_EnO13   SCN-CHP EnO in Coalition 13 with the HEN [kt CO2e per year]
SCN_CHP_EnO123  SCN-CHP EnO in Coalition 123 [kt CO2e per year]
SCN_CHP_EnO14   SCN-CHP EnO in Coalition 14 with the Farm [kt CO2e per year]
SCN_CHP_EnO124  SCN-CHP EnO in Coalition 124 with the MEE and the Farm [kt CO2e per year]
SCN_CHP_EnO134  SCN-CHP EnO in Coalition 134 with the HEN and the Farm [kt CO2e per year]
SCN_CHP_EnO1234 SCN-CHP EnO in Coalition 1234 [kt CO2e per year]
*MEE
MEE_EnO2    EnO of the stand-alone MEE [kt CO2e per year]
MEE_EnO12   MEE EnO in Coalition 12 [kt CO2e per year]
MEE_EnO23   MEE EnO in Coalition 23 [kt CO2e per year]
MEE_EnO123  MEE EnO in Coalition 123 [kt CO2e per year]
MEE_EnO24   MEE EnO in Coalition 24 with the Farm [kt CO2e per year]
MEE_EnO124  MEE EnO in Coalition 124 [kt CO2e per year]
MEE_EnO234  MEE EnO in Coalition 234 [kt CO2e per year]
MEE_EnO1234 MEE EnO in Coalition 1234 [kt CO2e per year]
*HEN
HEN_EnO     EnO of the stand-alone HEN [kt CO2e per year]
HEN_EnO13   HEN EnO in Coalition 13 [kt CO2e per year]
HEN_EnO23   HEN EnO in Coalition 23 [kt CO2e per year]
HEN_EnO123  HEN EnO in Coalition 123 [kt CO2e per year]
HEN_EnO34   HEN EnO in Coalition 34 with the Farm [kt CO2e per year]
HEN_EnO134  HEN EnO in Coalition 134 [kt CO2e per year]
HEN_EnO234  HEN EnO in Coalition 234 [kt CO2e per year]
HEN_EnO1234 HEN EnO in Coalition 1234 [kt CO2e per year]
*Farm
CR_EnO4     EnO of the stand-alone Farm [kt CO2e per year]
CR_EnO24    Farm EnO in Coalition 24 [kt CO2e per year]
CR_EnO34    Farm EnO in Coalition 34 [kt CO2e per year]
CR_EnO234   Farm EnO in Coalition 234 [kt CO2e per year]
CR_EnO14    Farm EnO in Coalition 14 [kt CO2e per year]
CR_EnO124   Farm EnO in Coalition 124 [kt CO2e per year]
CR_EnO134   Farm EnO in Coalition 134 [kt CO2e per year]
CR_EnO1234  Farm EnO in Coalition 1234 [kt CO2e per year];

Equations
*SCN-CHP
ESCN_CHP_EnO        EnO of the stand-alone SCN-CHP
ESCN_CHP_EnO12      SCN-CHP EnO in Coalition 12
ESCN_CHP_EnO13      SCN-CHP EnO in Coalition 13
ESCN_CHP_EnO123     SCN-CHP EnO in Coalition 123
ESCN_CHP_EnO14      SCN-CHP EnO in Coalition 14
ESCN_CHP_EnO124     SCN-CHP EnO in Coalition 124
ESCN_CHP_EnO134     SCN-CHP EnO in Coalition 134
ESCN_CHP_EnO1234    SCN-CHP EnO in Coalition 1234
*MEE
EMEE_EnO2           EnO of the stand-alone MEE
EMEE_EnO12          MEE EnO in Coalition 12
EMEE_EnO23          MEE EnO in Coalition 23
EMEE_EnO123         MEE EnO in Coalition 123
EMEE_EnO24          MEE EnO in Coalition 24
EMEE_EnO124         MEE EnO in Coalition 124
EMEE_EnO234         MEE EnO in Coalition 234
EMEE_EnO1234        MEE EnO in Coalition 1234
*HEN
EHEN_EnO3           EnO of the stand-alone HEN
EHEN_EnO13          HEN EnO in Coalition 13
EHEN_EnO23          HEN EnO in Coalition 23
EHEN_EnO123         HEN EnO in Coalition 123
EHEN_EnO34          HEN EnO in Coalition 34
EHEN_EnO134         HEN EnO in Coalition 134
EHEN_EnO234         HEN EnO in Coalition 234
EHEN_EnO1234        HEN EnO in Coalition 1234
*Farm
ECR_EnO4            EnO of the stand-alone Farm
ECR_EnO24           Farm EnO in Coalition 24
ECR_EnO34           Farm EnO in Coalition 34
ECR_EnO234          Farm EnO in Coalition 234
ECR_EnO14           Farm EnO in Coalition 14
ECR_EnO124          Farm EnO in Coalition 124
ECR_EnO134          Farm EnO in Coalition 134
ECR_EnO1234         Farm EnO in Coalition 1234;

*SCN-CHP: boiler and freight CO2 plus cooling water (as in its EcO)
ESCN_CHP_EnO$act('1')..
    SCN_CHP_EnO =e= EmissionsB + EmissionsT + Wt_Total*CO2e('CW')*OH*3600*1e-6;
ESCN_CHP_EnO12$act('12')..
    SCN_CHP_EnO12 =e= EmissionsB + EmissionsT + wt_totalA*CO2e('CW')*OH*3600*1e-6;
ESCN_CHP_EnO13$act('13')..
    SCN_CHP_EnO13 =e= EmissionsB + EmissionsT + wt_totalB*CO2e('CW')*OH*3600*1e-6;
ESCN_CHP_EnO123$act('123')..
    SCN_CHP_EnO123 =e= EmissionsB + EmissionsT + wt_totalc*CO2e('CW')*OH*3600*1e-6;
ESCN_CHP_EnO14$act('14')..
    SCN_CHP_EnO14 =e= EmissionsB + EmissionsT + Wt_Total*CO2e('CW')*OH*3600*1e-6;
ESCN_CHP_EnO124$act('124')..
    SCN_CHP_EnO124 =e= EmissionsB + EmissionsT + wt_totalA*CO2e('CW')*OH*3600*1e-6;
ESCN_CHP_EnO134$act('134')..
    SCN_CHP_EnO134 =e= EmissionsB + EmissionsT + wt_totalB*CO2e('CW')*OH*3600*1e-6;
ESCN_CHP_EnO1234$act('1234')..
    SCN_CHP_EnO1234 =e= EmissionsB + EmissionsT + wt_totalc*CO2e('CW')*OH*3600*1e-6;

*MEE: LPS bought without the SCN-CHP
EMEE_EnO2$act('2')..
    MEE_EnO2 =e= (MS + m_st)*CO2e('LPS')*OH*3600*1e-6;
EMEE_EnO12$act('12')..
    MEE_EnO12 =e= 0;
EMEE_EnO23$act('23')..
    MEE_EnO23 =e= (MS + m_st)*CO2e('LPS')*OH*3600*1e-6;
EMEE_EnO123$act('123')..
    MEE_EnO123 =e= 0;
EMEE_EnO24$act('24')..
    MEE_EnO24 =e= (MS + m_st)*CO2e('LPS')*OH*3600*1e-6;
EMEE_EnO124$act('124')..
    MEE_EnO124 =e= 0;
EMEE_EnO234$act('234')..
    MEE_EnO234 =e= (MS + m_st)*CO2e('LPS')*OH*3600*1e-6;
EMEE_EnO1234$act('1234')..
    MEE_EnO1234 =e= 0;

*HEN: bought steam (BuyHEN with the SCN-CHP) and chilled water
EHEN_EnO3$act('3')..
    HEN_EnO =e= (FlowHEN1*CO2e('HPS') + FlowHEN2*CO2e('MPS') + FlowHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;
EHEN_EnO13$act('13')..
    HEN_EnO13 =e= (BuyHEN1*CO2e('HPS') + BuyHEN2*CO2e('MPS') + BuyHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;
EHEN_EnO23$act('23')..
    HEN_EnO23 =e= (FlowHEN1*CO2e('HPS') + FlowHEN2*CO2e('MPS') + FlowHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;
EHEN_EnO123$act('123')..
    HEN_EnO123 =e= (BuyHEN1*CO2e('HPS') + BuyHEN2*CO2e('MPS') + BuyHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;
EHEN_EnO34$act('34')..
    HEN_EnO34 =e= (FlowHEN1*CO2e('HPS') + FlowHEN2*CO2e('MPS') + FlowHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;
EHEN_EnO134$act('134')..
    HEN_EnO134 =e= (BuyHEN1*CO2e('HPS') + BuyHEN2*CO2e('MPS') + BuyHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;
EHEN_EnO234$act('234')..
    HEN_EnO234 =e= (FlowHEN1*CO2e('HPS') + FlowHEN2*CO2e('MPS') + FlowHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;
EHEN_EnO1234$act('1234')..
    HEN_EnO1234 =e= (BuyHEN1*CO2e('HPS') + BuyHEN2*CO2e('MPS') + BuyHEN3*CO2e('LPS') + F_CUT*CO2e('CW'))*OH*3600*1e-6;

*Farm: grid power [kW] x HY / 1000 is MWh; CR_Fcw is a mean over OH; CHP power is in the SCN-CHP EnO
ECR_EnO4$act('4')..
    CR_EnO4 =e= (CO2e('Elec')*CR_Pgr*HY/1000 + CO2e('CW')*CR_Fcw*3600*OH/1000)/1000;
ECR_EnO24$act('24')..
    CR_EnO24 =e= (CO2e('Elec')*CR_Pgr*HY/1000 + CO2e('CW')*CR_Fcw*3600*OH/1000)/1000;
ECR_EnO34$act('34')..
    CR_EnO34 =e= (CO2e('Elec')*CR_Pgr*HY/1000 + CO2e('CW')*CR_Fcw*3600*OH/1000)/1000;
ECR_EnO234$act('234')..
    CR_EnO234 =e= (CO2e('Elec')*CR_Pgr*HY/1000 + CO2e('CW')*CR_Fcw*3600*OH/1000)/1000;
ECR_EnO14$act('14')..
    CR_EnO14 =e= CO2e('CW')*CR_Fcw*3600*OH*1e-6;
ECR_EnO124$act('124')..
    CR_EnO124 =e= CO2e('CW')*CR_Fcw*3600*OH*1e-6;
ECR_EnO134$act('134')..
    CR_EnO134 =e= CO2e('CW')*CR_Fcw*3600*OH*1e-6;
ECR_EnO1234$act('1234')..
    CR_EnO1234 =e= CO2e('CW')*CR_Fcw*3600*OH*1e-6;

*==============================================================================================================
*OBJECTIVE
*==============================================================================================================
*--OBJ=MOO first minimises EcO and EnO each on its own (bestEcO, bestEnO; points RG = 1 and RG = 0), then MOO_OBJFN for
*each weight RG in between (see SOLVE)
Sets
RG_set              Points of the MOO sweep     /RG1*RG5/;

Alias (RG_set, RG_pt);

Parameters
RGAA(RG_set)        Weight of the EcO at each MOO point (--RG2 --RG3 --RG4)             /RG1 0,
                                                                                        RG2 %RG2%,
                                                                                        RG3 %RG3%,
                                                                                        RG4 %RG4%,
                                                                                        RG5 1/
RG                  Weight of the EcO at the MOO point solved                           /1/
RGpos               Position in RG_set of the MOO point solved on the way down
bestEcO             Lowest EcO of the Coalition solved [1e5 $ per year]                 /1/
bestEnO             Lowest EnO of the Coalition solved [kt CO2e per year]               /1/
EnOtol              Relative slack on bestEnO for the EcO solve of the point RG = 0     /1e-6/
rg0EcO              Lowest EcO of a usable EcO solve at RG = 0 [1e5 $ per year]         /inf/
scaleEcO            EcO scale in MOO_OBJFN (bestEcO but at least 1) [1e5 $ per year]    /1/
scaleEnO            EnO scale in MOO_OBJFN (bestEnO but at least 1) [kt CO2e per year]  /1/
EcO_store(RG_set)   EcO at each MOO point [1e5 $ per year]
EnO_store(RG_set)   EnO at each MOO point [kt CO2e per year];

Variables
EcO_OBJFN       Objective for --OBJ=EcO: EcO of the Coalition solved (--COAL) [1e5 $ per year]
EnO_OBJFN       Objective for --OBJ=EnO: EnO of the Coalition solved [kt CO2e per year]
MOO_OBJFN       Objective for --OBJ=MOO: EcO and EnO each over its lowest value and weighted by RG and 1 - RG;

Equations
EEcO_OBJFN      EcO of the Coalition solved
EEnO_OBJFN      EnO of the Coalition solved
EMOO_OBJFN      Weighted sum of the scaled EcO and EnO;

EEcO_OBJFN..
    EcO_OBJFN =e=
    SCN_CHP_EcOA$solved('1') + MEE_EcO2$solved('2') + HEN_EcO$solved('3') + CR_EcO4$solved('4')
  + (SCN_CHP_EcOA12 + MEE_EcO12)$solved('12') + (SCN_CHP_EcOA13 + HEN_EcO13)$solved('13') + (SCN_CHP_EcOA14 + CR_EcO14)$solved('14')
  + (MEE_EcO23 + HEN_EcO23)$solved('23') + (MEE_EcO24 + CR_EcO24)$solved('24') + (HEN_EcO34 + CR_EcO34)$solved('34')
  + (SCN_CHP_EcOA123 + MEE_EcO123 + HEN_EcO123)$solved('123') + (SCN_CHP_EcOA124 + MEE_EcO124 + CR_EcO124)$solved('124')
  + (SCN_CHP_EcOA134 + HEN_EcO134 + CR_EcO134)$solved('134') + (MEE_EcO234 + HEN_EcO234 + CR_EcO234)$solved('234')
  + (SCN_CHP_EcOA1234 + MEE_EcO1234 + HEN_EcO1234 + CR_EcO1234)$solved('1234');

EEnO_OBJFN..
    EnO_OBJFN =e=
    SCN_CHP_EnO$solved('1') + MEE_EnO2$solved('2') + HEN_EnO$solved('3') + CR_EnO4$solved('4')
  + (SCN_CHP_EnO12 + MEE_EnO12)$solved('12') + (SCN_CHP_EnO13 + HEN_EnO13)$solved('13') + (SCN_CHP_EnO14 + CR_EnO14)$solved('14')
  + (MEE_EnO23 + HEN_EnO23)$solved('23') + (MEE_EnO24 + CR_EnO24)$solved('24') + (HEN_EnO34 + CR_EnO34)$solved('34')
  + (SCN_CHP_EnO123 + MEE_EnO123 + HEN_EnO123)$solved('123') + (SCN_CHP_EnO124 + MEE_EnO124 + CR_EnO124)$solved('124')
  + (SCN_CHP_EnO134 + HEN_EnO134 + CR_EnO134)$solved('134') + (MEE_EnO234 + HEN_EnO234 + CR_EnO234)$solved('234')
  + (SCN_CHP_EnO1234 + MEE_EnO1234 + HEN_EnO1234 + CR_EnO1234)$solved('1234');

EMOO_OBJFN..
    MOO_OBJFN =e= RG*EcO_OBJFN/scaleEcO + (1 - RG)*EnO_OBJFN/scaleEnO;

*Member EcO and EnO at the last solve. MEMBER_EcO_EnO is a macro: every line but the last ends in a backslash
Parameters
EcOm(player)                EcO of each member in the Coalition solved [1e5 $ per year]
EnOm(player)                EnO of each member in the Coalition solved [kt CO2e per year]
EcOm_store(RG_set,player)   EcO of each member at each MOO point [1e5 $ per year]
EnOm_store(RG_set,player)   EnO of each member at each MOO point [kt CO2e per year];

$macro MEMBER_EcO_EnO \
EcOm('1') = SCN_CHP_EcOA.l$solved('1') + SCN_CHP_EcOA12.l$solved('12') + SCN_CHP_EcOA13.l$solved('13') + SCN_CHP_EcOA14.l$solved('14') \
  + SCN_CHP_EcOA123.l$solved('123') + SCN_CHP_EcOA124.l$solved('124') + SCN_CHP_EcOA134.l$solved('134') + SCN_CHP_EcOA1234.l$solved('1234'); \
EcOm('2') = MEE_EcO2.l$solved('2') + MEE_EcO12.l$solved('12') + MEE_EcO23.l$solved('23') + MEE_EcO24.l$solved('24') \
  + MEE_EcO123.l$solved('123') + MEE_EcO124.l$solved('124') + MEE_EcO234.l$solved('234') + MEE_EcO1234.l$solved('1234'); \
EcOm('3') = HEN_EcO.l$solved('3') + HEN_EcO13.l$solved('13') + HEN_EcO23.l$solved('23') + HEN_EcO34.l$solved('34') \
  + HEN_EcO123.l$solved('123') + HEN_EcO134.l$solved('134') + HEN_EcO234.l$solved('234') + HEN_EcO1234.l$solved('1234'); \
EcOm('4') = CR_EcO4.l$solved('4') + CR_EcO14.l$solved('14') + CR_EcO24.l$solved('24') + CR_EcO34.l$solved('34') \
  + CR_EcO124.l$solved('124') + CR_EcO134.l$solved('134') + CR_EcO234.l$solved('234') + CR_EcO1234.l$solved('1234'); \
EnOm('1') = SCN_CHP_EnO.l$solved('1') + SCN_CHP_EnO12.l$solved('12') + SCN_CHP_EnO13.l$solved('13') + SCN_CHP_EnO14.l$solved('14') \
  + SCN_CHP_EnO123.l$solved('123') + SCN_CHP_EnO124.l$solved('124') + SCN_CHP_EnO134.l$solved('134') + SCN_CHP_EnO1234.l$solved('1234'); \
EnOm('2') = MEE_EnO2.l$solved('2') + MEE_EnO12.l$solved('12') + MEE_EnO23.l$solved('23') + MEE_EnO24.l$solved('24') \
  + MEE_EnO123.l$solved('123') + MEE_EnO124.l$solved('124') + MEE_EnO234.l$solved('234') + MEE_EnO1234.l$solved('1234'); \
EnOm('3') = HEN_EnO.l$solved('3') + HEN_EnO13.l$solved('13') + HEN_EnO23.l$solved('23') + HEN_EnO34.l$solved('34') \
  + HEN_EnO123.l$solved('123') + HEN_EnO134.l$solved('134') + HEN_EnO234.l$solved('234') + HEN_EnO1234.l$solved('1234'); \
EnOm('4') = CR_EnO4.l$solved('4') + CR_EnO14.l$solved('14') + CR_EnO24.l$solved('24') + CR_EnO34.l$solved('34') \
  + CR_EnO124.l$solved('124') + CR_EnO134.l$solved('134') + CR_EnO234.l$solved('234') + CR_EnO1234.l$solved('1234');

*USABLE: CGT returned a solution
$macro USABLE (CGT.modelstat = 1 or CGT.modelstat = 2 or CGT.modelstat = 8)

*MOO_STORE keeps the EcO and EnO (Coalition and members) at the point RG and saves every symbol in point_<point>.gdx;
*RG0_KEEP stores a EcO solve at RG = 0 that ran to the end with a lower EcO than rg0EcO
$macro MOO_STORE \
MEMBER_EcO_EnO \
EcO_store(RG_set)$(RGAA(RG_set) = RG)           = EcO_OBJFN.l; \
EnO_store(RG_set)$(RGAA(RG_set) = RG)           = EnO_OBJFN.l; \
EcOm_store(RG_set,player)$(RGAA(RG_set) = RG)   = EcOm(player); \
EnOm_store(RG_set,player)$(RGAA(RG_set) = RG)   = EnOm(player); \
loop(RG_pt$(RGAA(RG_pt) = RG), put_utility 'gdxout' / 'point_' RG_pt.tl:0 '.gdx'; execute_unload;);

$macro RG0_KEEP \
if(USABLE and CGT.solvestat = 1 and EcO_OBJFN.l < rg0EcO - 1e-6, \
    rg0EcO = EcO_OBJFN.l; \
    MOO_STORE \
    execute_unload 'moo_ei.gdx'; \
);

*==============================================================================================================
*SOLVE
*==============================================================================================================
MODEL CGT /all/;

*FIX_DESIGN saves the bounds of the integers and fixes the integers at their levels; FREE_DESIGN restores the bounds
Parameters
y_lo(i,j,k)     Lower bound of y
y_up(i,j,k)     Upper bound of y
z_lo(sp,f)      Lower bound of z
z_up(sp,f)      Upper bound of z
int_lo(*)       Lower bounds of the integers S_A NEFF b_PH b_cr b_crB and b_crS
int_up(*)       Upper bounds of the integers S_A NEFF b_PH b_cr b_crB and b_crS;

$macro FIX_DESIGN \
y_lo(i,j,k)                 = y.lo(i,j,k); \
y_up(i,j,k)                 = y.up(i,j,k); \
z_lo(sp,f)                  = z.lo(sp,f); \
z_up(sp,f)                  = z.up(sp,f); \
int_lo('S_A')               = S_A.lo; \
int_up('S_A')               = S_A.up; \
int_lo('NEFF')              = NEFF.lo; \
int_up('NEFF')              = NEFF.up; \
int_lo('b_PH')              = b_PH.lo; \
int_up('b_PH')              = b_PH.up; \
int_lo('b_cr')              = b_cr.lo; \
int_up('b_cr')              = b_cr.up; \
int_lo('b_crB')             = b_crB.lo; \
int_up('b_crB')             = b_crB.up; \
int_lo('b_crS')             = b_crS.lo; \
int_up('b_crS')             = b_crS.up; \
y.fx(i,j,k)$match(i,j,k)    = round(y.l(i,j,k)); \
S_A.fx                      = round(S_A.l); \
NEFF.fx                     = round(NEFF.l); \
z.fx(sp,f)                  = round(z.l(sp,f)); \
b_PH.fx                     = round(b_PH.l); \
b_cr.fx                     = 1$(CR_Cap.l > 0); \
b_crB.fx                    = round(b_crB.l); \
b_crS.fx                    = round(b_crS.l);

$macro FREE_DESIGN \
y.lo(i,j,k)     = y_lo(i,j,k); \
y.up(i,j,k)     = y_up(i,j,k); \
z.lo(sp,f)      = z_lo(sp,f); \
z.up(sp,f)      = z_up(sp,f); \
S_A.lo          = int_lo('S_A'); \
S_A.up          = int_up('S_A'); \
NEFF.lo         = int_lo('NEFF'); \
NEFF.up         = int_up('NEFF'); \
b_PH.lo         = int_lo('b_PH'); \
b_PH.up         = int_up('b_PH'); \
b_cr.lo         = int_lo('b_cr'); \
b_cr.up         = int_up('b_cr'); \
b_crB.lo        = int_lo('b_crB'); \
b_crB.up        = int_up('b_crB'); \
b_crS.lo        = int_lo('b_crS'); \
b_crS.up        = int_up('b_crS');

*Warm start (--START=<file>.gdx): load an earlier EcO solution of the same Coalition and fix its integers. The second
*loadpoint names the integers so GAMS treats their levels as set, and CR_Cap, which gives b_cr. --OBJ=MOO fixes them for
*RG = 1 only
$ifThen set START
$ifI %OBJ% == EnO $abort --START fixes the integers of a EcO solution, so it does not work with --OBJ=EnO
execute_loadpoint '%START%';
execute_loadpoint '%START%', y, S_A, NEFF, z, b_PH, b_crB, b_crS, CR_Cap;

*Cross-seeding: replace one player's design in the start by its design in another solution. execute_loadpoint skips
*zero levels, so the player's levels are cleared first
$ifThen set SEED
$ifThen %SEEDPLAYER% == 1
S_A.l = 0; z.l(sp,f) = 0; x.l(sp,f,s) = 0; bb.l(sp,s) = 0;
execute_loadpoint '%SEED%', S_A, z, x, bb;
$elseIf %SEEDPLAYER% == 2
NEFF.l = 0; b_PH.l = 0;
execute_loadpoint '%SEED%', NEFF, b_PH;
$elseIf %SEEDPLAYER% == 3
y.l(i,j,k) = 0; q.l(i,j,k) = 0; th.l(i,k) = 0; tc.l(j,k) = 0; dt.l(i,j,k) = 0;
execute_loadpoint '%SEED%', y, q, th, tc, dt;
$elseIf %SEEDPLAYER% == 4
b_cr.l = 0; b_crB.l = 0; b_crS.l = 0; CR_Cap.l = 0; CR_Pco.l = 0; CR_Pgr.l = 0; Q_crB.l = 0; Q_crS.l = 0;
execute_loadpoint '%SEED%', b_cr, b_crB, b_crS, CR_Cap, CR_Pco, CR_Pgr, Q_crB, Q_crS;
$else
$abort --SEEDPLAYER must be 1, 2, 3 or 4
$endIf
$endIf
FIX_DESIGN
$endIf

*Solver scaling: the large cost variables reach the solver in 1e5 $ per year (the EcO unit); condenser, Farm-exchanger
*and water costs and supply-chain kW are unscaled. Reported levels, bounds and marginals keep their units
CGT.scaleopt                = 1;
TFC.scale(f,sp,s)           = EcOunit;
TotalFuelCost.scale(f,sp,s) = EcOunit;
TFC2.scale(f,sp)            = EcOunit;
TotalFuelCost2.scale(f,sp)  = EcOunit;
TFC2_SUM.scale              = EcOunit;
Etfc2.scale                 = EcOunit;
SA_cst.scale                = EcOunit;
ESA_cst.scale               = EcOunit;
SCN_CHP_com.scale           = EcOunit;
ESCN_CHP_com.scale          = EcOunit;
CHP_cst.scale               = EcOunit;
ECHP_cst.scale              = EcOunit;
ASP.scale                   = 1e3;
AreaSP.scale                = 1e3;
AFC.scale                   = EcOunit;
EqAFC.scale                 = EcOunit;
AOC2.scale                  = EcOunit;
EqAOC.scale                 = EcOunit;
HENcap.scale                = EcOunit;
EHENcap.scale               = EcOunit;
TERM1.scale                 = EcOunit;
TERM2.scale                 = EcOunit;
ETERM1.scale                = EcOunit;
ETERM2.scale                = EcOunit;
HUT_Cst.scale               = EcOunit;
EHUT_Cst.scale              = EcOunit;
HUT_Cst13.scale             = EcOunit;
EHUT_Cst13.scale            = EcOunit;
CUT_Cst.scale               = EcOunit;
ECUT_Cst.scale              = EcOunit;
AOC_HEN.scale               = EcOunit;
AOC_HEN_1.scale             = EcOunit;
Q_fw.scale                  = 1e4;
FeedQ.scale                 = 1e4;
CR_capc.scale               = EcOunit;
CR_capE.scale               = EcOunit;
CR_rev.scale                = EcOunit;
CR_revE.scale               = EcOunit;
CR_grid.scale               = EcOunit;
CR_gridE.scale              = EcOunit;

option minlp = dicopt;
option mip = cplex;
option nlp = conopt;
option rminlp = conopt;
*After each solve, variables the Coalition does not use go back to 0, so the GDX files hold only the Coalition's levels
option solveOpt = clear;

$ifThenI %OBJ% == MOO
*The EcO solve (warm with --START) and the EnO solve give bestEcO, bestEnO and the points RG = 1 and RG = 0. The points in
*between are solved twice, up from the EnO solve and down from the EcO solve (moo_tac.gdx), each from its neighbour, and
*keep the lower MOO_OBJFN. A solve with no solution stops the run going up and is skipped going down, except the last,
*whose levels the results read
RG = 1;
solve CGT using rminlp minimizing EcO_OBJFN;
solve CGT using minlp minimizing EcO_OBJFN;
abort$(not USABLE) 'CGT returned no solution at this MOO point', RG, CGT.modelstat;
MOO_STORE
bestEcO = EcO_OBJFN.l;
execute_unload 'moo_tac.gdx';
$ifThen set START
*The integers are free again after the warm EcO solve
FREE_DESIGN
$endIf
RG = 0;
solve CGT using minlp minimizing EnO_OBJFN;
abort$(not USABLE) 'CGT returned no solution at this MOO point', RG, CGT.modelstat;
MOO_STORE
bestEnO = EnO_OBJFN.l;
*The floor of 1 keeps MOO_OBJFN defined for a Coalition whose lowest EcO or EnO is 0 or below (the Farm alone, not built)
scaleEcO = max(bestEcO, 1);
scaleEnO = max(bestEnO, 1);
*The EnO solve leaves its EcO arbitrary, and can stop early with levels far out, so RG = 0 is solved again for the
*lowest EcO with the EnO within EnOtol of bestEnO: with the integers of the EnO solve fixed, from the EnO solve and from the
*EcO solve; free from the first of those; free from the EcO solve. RG = 0 keeps the lowest EcO (the EnO solve if all
*fail) and the way up starts from it (moo_ei.gdx)
EnO_OBJFN.up = bestEnO*(1 + EnOtol);
execute_unload 'moo_ei.gdx';
FIX_DESIGN
solve CGT using rminlp minimizing EcO_OBJFN;
RG0_KEEP
execute_unload 'moo_rg0.gdx';
execute_loadpoint 'moo_tac.gdx';
solve CGT using rminlp minimizing EcO_OBJFN;
RG0_KEEP
FREE_DESIGN
execute_loadpoint 'moo_rg0.gdx';
solve CGT using minlp minimizing EcO_OBJFN;
RG0_KEEP
execute_loadpoint 'moo_tac.gdx';
solve CGT using rminlp minimizing EcO_OBJFN;
solve CGT using minlp minimizing EcO_OBJFN;
RG0_KEEP
execute_loadpoint 'moo_ei.gdx';
EnO_OBJFN.up = inf;

loop(RG_set$(RGAA(RG_set) > 0 and RGAA(RG_set) < 1),
    RG = RGAA(RG_set);
    solve CGT using minlp minimizing MOO_OBJFN;
    abort$(not USABLE) 'CGT returned no solution at this MOO point', RG, CGT.modelstat;
    MOO_STORE
);

*execute_loadpoint skips zero levels, so variables that are zero in the EcO solve keep their levels from the RG4 point
execute_loadpoint 'moo_tac.gdx';
for(RGpos = card(RG_set) downto 1,
    loop(RG_set$(ord(RG_set) = RGpos and RGAA(RG_set) > 0 and RGAA(RG_set) < 1),
        RG = RGAA(RG_set);
        solve CGT using minlp minimizing MOO_OBJFN;
        if(USABLE and MOO_OBJFN.l < RG*EcO_store(RG_set)/scaleEcO + (1 - RG)*EnO_store(RG_set)/scaleEnO - 1e-6,
            MOO_STORE
        );
    );
);
$else
solve CGT using rminlp minimizing %OBJ%_OBJFN;
solve CGT using minlp minimizing %OBJ%_OBJFN;
$endIf

*Results come from the last solve (the RG2 point going down for MOO)
abort$(not USABLE) 'CGT returned no solution', CGT.modelstat;

*==============================================================================================================
*RESULTS
*==============================================================================================================
*run_coalitions.py reads EcOm, EnOm, res, OBJ_run and the MOO stores from the GDX of each run, and the variables at each
*MOO point from point_<point>.gdx
Sets
item            Results of the Coalition solved /'model status', 'EcO', 'EnO'/
OBJ_run         Objective minimised in this run (--OBJ) /%OBJ%/;

Parameters
res(item)       Model status and EcO [1e5 $ per year] and EnO [kt CO2e per year] of the last solve;

MEMBER_EcO_EnO

res('model status') = CGT.modelstat;
res('EcO')          = EcO_OBJFN.l;
res('EnO')          = EnO_OBJFN.l;
