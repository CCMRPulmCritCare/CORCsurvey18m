version 17
set more off
clear all
set linesize 80
cap log close

cd ""

local day : display %tdCYND daily("$S_DATE", "DMY")
di "`day'"

log using "corc_18m_JAMA_NO_`day'.log", replace

*--------------------------------------------------------
* Project:      CORC 18-month Survey 
* Created:      2023 Jan 9		
* Last updated: 2023 Dec 19
* Author:       Sarah Seelye
*--------------------------------------------------------

*--------------------------------
* Data Import and Organization
*--------------------------------

* Create Analytic Cohort with 1 COVID+ and 1 Comparator per Dyad 

/*			
* import survey data 
import delimited "corc_lto_18m_data_V3.csv", clear

* reorder variables 
order dod sex redcap_event_name redcap_repeat_instrument redcap_repeat_instance ///
		studystatus m18start-survey_end_time_prox case_reached___1-control5_priority ///
		consent_agree-mail2_compyn_m18_prox___1, last
order surveystatus_m18, after(sampling_wt)
		
* create new survey identifier 
gen surveynum = .
replace surveynum = 1 if redcap_event_name=="baseline"
replace surveynum = 2 if redcap_event_name=="month_18"
label define surveynum 1 "Baseline" 2 "18 Month", replace
lab val surveynum surveynum

order surveynum, after(sampling_wt)

tab surveynum 

* identify completed surveys 
tab surveynum surveystatus_m18 , m //n=475 completed; 4 withdrew; 67 suspended

* replace missing values for 18 month survey information
bysort patienticn (surveynum): replace cohort_group = cohort_group[_n-1] if cohort_group==.
bysort patienticn (surveynum): replace covid = covid[_n-1] if covid==.
bysort patienticn (surveynum): replace cohort_monthyear = cohort_monthyear[_n-1] if cohort_monthyear==""
bysort patienticn (surveynum): replace surveystatus_m18 = surveystatus_m18[_n-1] if surveystatus_m18==.

* male 
gen male = .
replace male = 1 if sex=="M" 
replace male = 0 if sex=="F" 

tab male sex, m

* age (at cohort month-year) 
gen dob2 = date(dob, "MDY")
format dob2 %td
order dob2, after(dob)

gen cohort_monthyear2 = date(cohort_monthyear, "MDY")
format cohort_monthyear2 %td 
order cohort_monthyear2, after(cohort_monthyear)

gen age = floor((cohort_monthyear2-dob2)/365.25)
order male age, after(dob2)

* keep one row per respondent
drop if surveynum==1

* keep only those who completed the 18 month survey 
keep if surveystatus_m18==1

* create new case/comparator variable 
gen case = covid==1
tab case covid
order case, before(covid)

* check numbers of cases and matched comparators - only include one case 
* and one comparator to form a dyad
gen control = case == 0
gsort matchgroupnumber -case
by matchgroupnumber: gen numinmatchgroup = _N
by matchgroupnumber: gen n = _n

	* case and matched comparator both present in matchgroup
	by matchgroupnumber: egen case_in_grp = max(case)
	by matchgroupnumber: egen control_in_grp = max(control)
	gen case_control_in_grp = .
	replace case_control_in_grp = 1 if case_in_grp==1 & control_in_grp==1
	replace case_control_in_grp = 0 if case_in_grp==0 | control_in_grp==0

	tab case_in_grp if n==1
	tab control_in_grp if n==1
	tab case_control_in_grp //n=70 have no matched pair
	tab case_control_in_grp if n==1 // n=194 matched pairs
	tab case_control_in_grp numinmatchgroup if n==1 //17 matchgroups have 2 comparators
	tab case_control_in_grp numinmatchgroup 

* drop matchgroups with no matched pair - there must be 1 case & 1 comparator 
drop if case_control_in_grp==0

* only keep one comparator per match group; keep the comparator with the 
* response date closest to the case's response date 
gen survey_stop_time_all = survey_stop_time 
replace survey_stop_time_all=survey_end_time_prox if survey_stop_time_all==""

gen double surveydatetime = clock(survey_stop_time_all, "MDYhm")
format surveydatetime %tc
gen surveydate = dofc(surveydatetime)
format surveydate %td

bysort matchgroupnumber (surveydatetime): gen surveyorder = _n
*br surveydate case matchgroup survey_stop_time_all if numinmatchgroup==3
tab case surveyorder //in the triads, the case is always interviewed first
drop if surveyorder==3  //surveyorder=3 is the comparator interviewed the 
						//furthest from the case. in some cases, the survey 
						//stop time is the same between two comparators, 
						//making the surveyorder number random. For this 
						//reason, the dataset will need to be locked

* confirm dyads - one case and one comparator per matchgroup 
drop numinmatchgroup n case_in_grp control_in_grp case_control_in_grp
by matchgroupnumber: gen numinmatchgroup = _N
by matchgroupnumber: gen n = _n
tab numinmatchgroup n
	
by matchgroupnumber: egen case_in_grp = max(case)
by matchgroupnumber: egen control_in_grp = max(control)
gen case_control_in_grp = .
replace case_control_in_grp = 1 if case_in_grp==1 & control_in_grp==1
replace case_control_in_grp = 0 if case_in_grp==0 | control_in_grp==0

tab case_control_in_grp // n=388 

drop control survey_stop_time_all surveydatetime surveyorder  ///
	 numinmatchgroup n case_in_grp control_in_grp case_control_in_grp 
					
* save analytic cohort 
*save Sarah\Disability_Paper\Data\corc_lto_18m_analytic_cohort, replace 
*/


*----------------------------
* Create a Response Weight
*----------------------------

* create a total weight (sampling_wt * predicted response weight) to use for 
* survey respondents among those who were COVID+

/*
	* open dataset created in first step above 
	use corc_lto_18m_analytic_cohort, clear
	
	* keep cohort variables needed to merge with dataset on VINCI;
	* only keep ids from the covid+ patients; weights will only be created 
	* for covid+ patients 
	keep record_id patienticn matchgroupnumber sampling_wt covid 
	keep if covid==1
	gen respondent_18m_survey = 1
	tempfile surveyids
	save `surveyids'

	* cohort 1	
	import excel "PatientUpload_04272022_v8.xlsx", ///
				sheet("PatientUpload_04272022_v8") firstrow case(lower) clear
	count //1619
	keep if covid==1 //keep only covid+ patients
	keep record_id patienticn matchgroupnumber sampling_wt dod 
	count //270
	drop if dod!=. //no one in this sample is deceased
	gen cohort1 = 1
	duplicates report record_id
	tempfile cohort1
	save `cohort1'
	
	* cohort 2 
	import excel "PatientUpload_07082022_v2.xlsx", ///
				sheet("PatientUpload_07082022_v2") firstrow case(lower) clear
	count //1668
	keep if covid==1
	keep record_id patienticn matchgroupnumber sampling_wt dod
	count //278
	drop if dod!=.  //no one in this sample is deceased
	gen cohort2 = 1 
	duplicates report record_id
	tempfile cohort2
	save `cohort2'
	
	* append cohort 1 and cohort 2 
	use `cohort1', clear
	append using `cohort2'
	count //548
	tempfile bothcohorts
	save `bothcohorts'
	
	* merge cohort 1 & 2 with survey sample
	use `surveyids', clear
	merge 1:1 record_id using `bothcohorts'
	
	* create a single variable to identify cohort 
	tab cohort1 cohort2, m
	gen cohort = .
	replace cohort = 1 if cohort1==1
	replace cohort = 2 if cohort2==1
	tab cohort
	
	* count survey respondents from each cohort
	tab respondent_18m_survey, m
	replace respondent_18m_survey=0 if respondent_18m_survey==.
	tab respondent_18m_survey cohort, co chi 
	
	* save dataset to use for making response weights
	drop cohort1 cohort2 _merge covid
	sort cohort patienticn
	count  //548
	save corc_survey_cohort1_2_covid, replace 
*/
	
* merge in response weights 
use corc_lto_18m_analytic_cohort, clear 
merge 1:1 record_id using corc_survey_18m_20230324
drop _merge 

count //388
 
* identify the main analytic cohort (cases and comparators that don't become infected)
gen analytic_cohort = futureinfected_matchgroup==0
tab analytic_cohort //372 participants, 186 matched pairs

* create new race & ethnicity variables
tab race3cat_25to1
tab race3cat_25to1, nol
gen black=race3cat_25to1==1
tab black race3cat_25to1

tab ethnicity3cat_25to1
tab ethnicity3cat_25to1, nol
gen hispanic=ethnicity3cat_25to1==1
tab hispanic ethnicity3cat_25to1	

*------------------------
* Life Space Assessment
*-------------------------


* Use Theodore Berkowitz's SAS code to create the CompositeLifeSpace 
* variable. Clone LSA variables; save and export dataset to SAS; run SAS
* code; and then merge in CompositeLifeSpace scores.   

/*		
		clonevar lsa_level1_yesno = lsm_rooms_visit_ind  
		clonevar lsa_level2_yesno = lsm_outside_visit_ind  
		clonevar lsa_level3_yesno = lsm_nhood_visit_ind 	
		clonevar lsa_level4_yesno = lsm_town_visit_ind 	
		clonevar lsa_level5_yesno = lsm_outoftown_visit_ind 

		clonevar lsa_level1_frequency = lsm_rooms_visit_freq 	 
		clonevar lsa_level2_frequency = lsm_outside_visit_freq	
		clonevar lsa_level3_frequency = lsm_nhood_visit_freq	
		clonevar lsa_level4_frequency = lsm_town_visit_freq	
		clonevar lsa_level5_frequency = lsm_outoftown_visit_freq 

		clonevar lsa_level1_aids_equip = lsm_rooms_aids_use
		clonevar lsa_level2_aids_equip = lsm_outside_aids_use
		clonevar lsa_level3_aids_equip = lsm_nhood_aids_use
		clonevar lsa_level4_aids_equip = lsm_town_aids_use	
		clonevar lsa_level5_aids_equip = lsm_outoftown_aids_use	

		clonevar lsa_level1_otherperson = lsm_rooms_help_others	
		clonevar lsa_level2_otherperson = lsm_outside_help_others 
		clonevar lsa_level3_otherperson = lsm_nhood_help_others	 
		clonevar lsa_level4_otherperson = lsm_town_help_others	 
		clonevar lsa_level5_otherperson = lsm_outoftown_help_others 

		* recode value of variables to match SAS code 
		recode lsa_level1_yesno (0=2)
		recode lsa_level2_yesno (0=2)
		recode lsa_level3_yesno (0=2)
		recode lsa_level4_yesno (0=2)
		recode lsa_level5_yesno (0=2)

		replace lsa_level1_frequency = lsa_level1_frequency+1
		replace lsa_level2_frequency = lsa_level2_frequency+1
		replace lsa_level3_frequency = lsa_level3_frequency+1
		replace lsa_level4_frequency = lsa_level4_frequency+1
		replace lsa_level5_frequency = lsa_level5_frequency+1

		recode lsa_level1_aids_equip (0=2)
		recode lsa_level2_aids_equip (0=2)
		recode lsa_level3_aids_equip (0=2)
		recode lsa_level4_aids_equip (0=2)
		recode lsa_level5_aids_equip (0=2)

		recode lsa_level1_otherperson (0=2)
		recode lsa_level2_otherperson (0=2)
		recode lsa_level3_otherperson (0=2)
		recode lsa_level4_otherperson (0=2)
		recode lsa_level5_otherperson (0=2)

		* clone proxy variables 
		clonevar lsa_level1_yesno_prox = lsm_rooms_visit_ind_prox 
		clonevar lsa_level2_yesno_prox  = lsm_outside_visit_ind_prox   
		clonevar lsa_level3_yesno_prox  = lsm_nhood_visit_ind_prox  	
		clonevar lsa_level4_yesno_prox  = lsm_town_visit_ind_prox  	
		clonevar lsa_level5_yesno_prox  = lsm_outoftown_visit_ind_prox  

		clonevar lsa_level1_frequency_prox  = lsm_rooms_visit_freq_prox  	 
		clonevar lsa_level2_frequency_prox  = lsm_outside_visit_freq_prox 	
		clonevar lsa_level3_frequency_prox  = lsm_nhood_visit_freq_prox 	
		clonevar lsa_level4_frequency_prox  = lsm_town_visit_freq_prox 	
		clonevar lsa_level5_frequency_prox  = lsm_outoftown_visit_freq_prox  

		clonevar lsa_level1_aids_equip_prox  = lsm_rooms_aids_use_prox 
		clonevar lsa_level2_aids_equip_prox  = lsm_outside_aids_use_prox 
		clonevar lsa_level3_aids_equip_prox  = lsm_nhood_aids_use_prox 
		clonevar lsa_level4_aids_equip_prox  = lsm_town_aids_use_prox 	
		clonevar lsa_level5_aids_equip_prox  = lsm_outoftown_aids_use_prox 	

		clonevar lsa_level1_otherperson_prox  = lsm_rooms_help_others_prox 	
		clonevar lsa_level2_otherperson_prox  = lsm_outside_help_others_prox  
		clonevar lsa_level3_otherperson_prox  = lsm_nhood_help_others_prox 	 
		clonevar lsa_level4_otherperson_prox  = lsm_town_help_others_prox 	 
		clonevar lsa_level5_otherperson_prox  = lsm_outoftown_help_others_prox  

		* recode value of proxy variables to match SAS code 
		recode lsa_level1_yesno_prox (0=2)
		recode lsa_level2_yesno_prox (0=2)
		recode lsa_level3_yesno_prox (0=2)
		recode lsa_level4_yesno_prox (0=2)
		recode lsa_level5_yesno_prox (0=2)

		replace lsa_level1_frequency_prox = lsa_level1_frequency_prox+1
		replace lsa_level2_frequency_prox = lsa_level2_frequency_prox+1
		replace lsa_level3_frequency_prox = lsa_level3_frequency_prox+1
		replace lsa_level4_frequency_prox = lsa_level4_frequency_prox+1
		replace lsa_level5_frequency_prox = lsa_level5_frequency_prox+1

		recode lsa_level1_aids_equip_prox (0=2)
		recode lsa_level2_aids_equip_prox (0=2)
		recode lsa_level3_aids_equip_prox (0=2)
		recode lsa_level4_aids_equip_prox (0=2)
		recode lsa_level5_aids_equip_prox (0=2)

		recode lsa_level1_otherperson_prox (0=2)
		recode lsa_level2_otherperson_prox (0=2)
		recode lsa_level3_otherperson_prox (0=2)
		recode lsa_level4_otherperson_prox (0=2)
		recode lsa_level5_otherperson_prox (0=2)

		* replace missing values with proxy values when they are available 
		forval i=1/5 {
			foreach var in 	lsa_level`i'_yesno 	///
						lsa_level`i'_frequency 	///	
						lsa_level`i'_aids_equip ///
						lsa_level`i'_otherperson {
				replace `var' = `var'_prox if `var'==. & `var'_prox!=.
			}
		}

		* keep lsa variables needed for SAS code & save dataset to run in SAS
			keep patienticn lsa_level1_yesno-lsa_level5_otherperson
			sort patienticn
			order patienticn
			outsheet using survey_18m_lsa.csv, comma replace
*/	


preserve

	* import updated CSV with new composite score created from SAS code 

	use survey_18m_lsacomposite, clear 
	keep  patienticn maximallifespace independentlifespace assistedlifespace compositelifespace

	* merge new composite score with dataset 
	tempfile lsa 
	save `lsa'
	
restore 

* use survey file to merge with lsa
merge 1:1 patienticn using `lsa'
drop _merge	

sum compositelifespace			

count //388

*------------------
* Count of ADLs
*------------------

	* adl_*
	* adl_*_prox

	* recode ADL values 2-5 
		* (2) Don't do => 0
		* (3) Can't do => 0
		* (4) Don't know => .
		* (5) Refused to answer => .

* respondent
tab adl_dressing , m
recode adl_dressing (3=0)

tab adl_walking, m 
recode adl_walking (2=0)

tab adl_bathing , m

tab adl_eating, m

tab adl_bed, m
recode adl_bed (3=0)

tab adl_toilet, m
recode adl_toilet (2=0)

tab adl_map, m
recode adl_map (2=0) (4=.)

tab adl_hotmeal, m
recode adl_hotmeal (2=0)

tab adl_groceries, m
recode adl_groceries (2=0)

tab adl_calls, m

tab adl_meds, m
recode adl_meds (2=0)

tab adl_money, m 
recode adl_money (2=0)

tab adl_stooping, m
recode adl_stooping (2=0) (3=0) (4=.)

tab adl_lift, m
recode adl_lift (2=0) (3=0)

* proxy
tab adl_dressing_prox , m
recode adl_dressing_prox (3=0)

tab adl_walking_prox, m 

tab adl_bathing_prox , m

tab adl_eating_prox, m

tab adl_bed_prox, m

tab adl_toilet_prox, m

tab adl_map_prox, m
recode adl_map_prox (2=0) 

tab adl_hotmeal_prox, m
recode adl_hotmeal_prox (2=0)

tab adl_groceries_prox, m
recode adl_groceries_prox (2=0)

tab adl_calls_prox, m

tab adl_meds_prox, m

tab adl_money_prox, m 
recode adl_money_prox (2=0)

tab adl_stooping_prox, m
recode adl_stooping_prox (3=0)

tab adl_lift_prox, m

foreach var in 	adl_dressing_prox adl_walking_prox adl_bathing_prox 	///
				adl_eating_prox adl_bed_prox adl_toilet_prox adl_map_prox 	///
				adl_hotmeal_prox adl_groceries_prox adl_calls_prox 	///
				adl_meds_prox adl_money_proxy adl_stooping_prox 	///
				adl_lift_prox { 
	tab `var' 
}

* create count of adls for respondents; keep missing as missing
egen adl_count = rowtotal(adl_dressing-adl_lift)
egen adl_miss = rowmiss(adl_dressing-adl_lift)	
tab adl_miss						  			  

* anyone with a missing response on a question receives a missing total count
replace adl_count = . if adl_miss>0

* create count of adls for proxies; keep missing as missing						  					  
egen adl_prox_count = rowtotal(adl_dressing_prox-adl_lift_prox)
tab adl_prox_count			  

egen adl_prox_miss = rowmiss(adl_dressing_prox-adl_lift_prox)

* replace missing ADL scores with proxy ADL scores when proxy scores are available
replace adl_count = adl_prox_count if adl_count==. & adl_prox_miss==0
						  
tab adl_count, m

tab adl_count case, co chi
tab adl_count case, co m

*----------
* Pain
*----------
	
	* eq_paindisc
	* eq_pain_prox

* participants
tab eq_paindisc, m
label def pain 1 "none" 2 "slight" 3 "moderate" 4 "severe" 5 "extreme"
label val eq_paindisc pain 

* proxies
tab eq_pain_prox, m
lab val eq_pain_prox pain

tab eq_paindisc eq_pain_prox, m

* create a combined variable
gen eq_pain_all = eq_paindisc
replace eq_pain_all = eq_pain_prox if eq_paindisc==.
lab val eq_pain_all pain
tab eq_pain_all, m

*------------
* Fatigue
*------------

* see Fatigue Scoring Manual

* sum participant scores 
egen fatigue_count = rowtotal(promis_tired-promis_exercise)
egen fatigue_miss = rowmiss(promis_tired-promis_exercise)
tab fatigue_count fatigue_miss, m

* replace total fatigue score as missing for anyone with a missing response
replace fatigue_count = . if fatigue_miss>0

* sum proxy scores 
egen fatigue_prox_count = rowtotal(promis_tired_prox-promis_exercise_freq_prox)
egen fatigue_prox_miss = rowmiss(promis_tired_prox-promis_exercise_freq_prox)
tab fatigue_prox_count fatigue_prox_miss

* replace missing fatigue score with proxy score when proxy score is available 
replace fatigue_count = fatigue_prox_count if fatigue_count==. & fatigue_prox_miss==0

tab fatigue_count, m
tab fatigue_count case, m
tab fatigue_count case, co chi

* use Fatigue 7a, Short Form Conversion Table for T-scores 
gen fatigue_tscore = fatigue_count
recode fatigue_tscore (7=29.4)(8=33.4)(9=36.9)(10=39.6)(11=41.9)(12=43.9) ///
					  (13=45.8)(14=47.6)(15=49.2)(16=50.8)(17=52.2)(18=53.7) ///
					  (19=55.1)(20=56.4)(21=57.8)(22=59.2)(23=60.6)(24=62.0) ///
					  (25=63.4)(26=64.8)(27=66.3)(28=67.8)(29=69.4)(30=71.1) ///
					  (31=72.9)(32=74.8)(33=77.1)(34=79.8)(35=83.2)

*-----------------
* Employment
*-----------------

	* employ
	* employ_prox 
	
tab employ , m	
tab employ_prox, m
tab employ employ_prox, m

* create a combined participant/proxy variable
gen employ_all_cat = employ 
replace employ_all_cat = employ_prox if employ==. & employ_prox<.
lab def employ 	1 "working" 2 "unemploy" 3 "laid off" 		///
				4 "disabled" 5 "retired" 6 "homemaker" 7 "other"
lab val employ_all_cat employ				
tab employ employ_all_cat, m

tab employ_all_cat, m

* create an indicator of employed/not employed 
gen employ_all_ind = employ_all_cat==1
tab employ_all_ind case, co chi

*----------------------
* Household Finances
*----------------------
	
	* ft_savings 		Used up all or most of your savings 
							* yes/no
	
	* ft_necessities	Unable to pay for necessities like food, heat, or housing
							* yes/no
	
	* ft_impact_health	Health been a drain on financial resources
							* 1) None
							* 2) Mild
							* 3) Moderate
							* 4) Severe
							* 5) Extreme

tab ft_savings, m
tab ft_necessities, m
tab ft_impact_health, m

tab ft_savings_prox, m
tab ft_necessities_prox, m
tab ft_impact_health_prox, m

tab ft_savings ft_savings_prox, m
tab ft_necessities ft_necessities_prox, m
tab ft_impact_health ft_impact_health_prox, m

* create combined participant/proxy variables
clonevar ft_savings_all = ft_savings
replace ft_savings_all = ft_savings_prox if ft_savings==. & ft_savings_prox<.

clonevar ft_necessities_all = ft_necessities
replace ft_necessities_all = ft_necessities_prox if ft_necessities==. & ft_necessities_prox<.

clonevar ft_impact_health_all = ft_impact_health
replace ft_impact_health_all = ft_impact_health_prox if ft_impact_health==. & ft_impact_health_prox<.

*-------------
* EQ-5D-5L
*-------------

tab eq_mobility eq_mobility_prox, m 
tab eq_selfcare eq_selfcare_prox, m
tab eq_usualactivities eq_usualactivities_prox, m
tab eq_paindisc eq_pain_prox, m
tab eq_anxietydep eq_anxietydepress_prox, m

* rename proxy variables to make them consistent with participant variables 
rename eq_pain_prox eq_paindisc_prox
rename eq_anxietydepress_prox eq_anxietydep_prox

* create combined participant/proxy variables

foreach var in 	eq_mobility eq_selfcare eq_usualactivities ///
				eq_paindisc eq_anxietydep {

	clonevar `var'_all = `var'
	replace `var'_all = `var'_prox if `var'==. & `var'_prox<.
}

* EQ-5D-5L code: https://euroqol.org/wp-content/uploads/2020/11/US_valueset_STATA.txt
* downloaded from: https://euroqol.org/support/analysis-tools/index-value-set-calculators/
gen disut_mo= . 
replace disut_mo= 0     if missing(disut_mo) & eq_mobility_all == 1
replace disut_mo= 0.096 if missing(disut_mo) & eq_mobility_all == 2
replace disut_mo= 0.122 if missing(disut_mo) & eq_mobility_all == 3
replace disut_mo= 0.237 if missing(disut_mo) & eq_mobility_all == 4
replace disut_mo= 0.322 if missing(disut_mo) & eq_mobility_all == 5

gen disut_sc= . 
replace disut_sc= 0     if missing(disut_sc) & eq_selfcare_all == 1
replace disut_sc= 0.089 if missing(disut_sc) & eq_selfcare_all == 2
replace disut_sc= 0.107 if missing(disut_sc) & eq_selfcare_all == 3
replace disut_sc= 0.220 if missing(disut_sc) & eq_selfcare_all == 4
replace disut_sc= 0.261 if missing(disut_sc) & eq_selfcare_all == 5

gen disut_ua= . 
replace disut_ua= 0     if missing(disut_ua) & eq_usualactivities_all == 1
replace disut_ua= 0.068 if missing(disut_ua) & eq_usualactivities_all == 2
replace disut_ua= 0.101 if missing(disut_ua) & eq_usualactivities_all == 3
replace disut_ua= 0.255 if missing(disut_ua) & eq_usualactivities_all == 4
replace disut_ua= 0.255 if missing(disut_ua) & eq_usualactivities_all == 5

gen disut_pd= . 
replace disut_pd= 0     if missing(disut_pd) & eq_paindisc_all == 1
replace disut_pd= 0.060 if missing(disut_pd) & eq_paindisc_all == 2
replace disut_pd= 0.098 if missing(disut_pd) & eq_paindisc_all == 3
replace disut_pd= 0.318 if missing(disut_pd) & eq_paindisc_all == 4
replace disut_pd= 0.414 if missing(disut_pd) & eq_paindisc_all == 5

gen disut_ad= . 
replace disut_ad= 0     if missing(disut_ad) & eq_anxietydep_all == 1
replace disut_ad= 0.057 if missing(disut_ad) & eq_anxietydep_all == 2
replace disut_ad= 0.123 if missing(disut_ad) & eq_anxietydep_all == 3
replace disut_ad= 0.299 if missing(disut_ad) & eq_anxietydep_all == 4
replace disut_ad= 0.321 if missing(disut_ad) & eq_anxietydep_all == 5

gen disut_total = disut_mo + disut_sc + disut_ua + disut_pd + disut_ad

gen EQindex=.
replace EQindex=1-disut_total
replace EQindex=round(EQindex,.001)

*---------------------------------
* Back to how you felt in 2020
*---------------------------------

tab covid_recovery, m
tab covid_recovery covid_recovery_prox, m

gen covid_recovery_all = .
replace covid_recovery_all = covid_recovery 
replace covid_recovery_all = covid_recovery_prox if covid_recovery_all==. 

*---------------------------
* Variables for Analyses
*---------------------------

tab adl_count case, co chi
version 16: table case, c(n adl_count mean adl_count median adl_count)
regress adl_count case
ttest adl_count, by(case)
kwallis adl_count, by(case)

tab eq_pain_all case, co chi nol
version 16: table case, c(n eq_pain_all mean eq_pain_all median eq_pain_all)
kwallis eq_pain_all, by(case)

version 16: table case, c(n fatigue_tscore mean fatigue_tscore median fatigue_tscore)
ttest fatigue_tscore, by(case)

tab employ_all_ind case, co chi

version 16: table case, c(mean compositelifespace median compositelifespace)
ttest compositelifespace, by(case)

tab ft_savings_all case, co chi 
tab ft_necessities_all case, co chi 
tab ft_impact_health_all case, co 
version 16: table case, c(mean ft_impact_health_all median ft_impact_health_all)
kwallis ft_impact_health_all, by(case)

version 16: table case, c(mean EQindex median EQindex)
ttest EQindex, by(case)

version 16: table case, c(mean phq9_score median phq9_score)
ttest phq9_score, by(case)

********************************************************************
* Recoding Baseline Covariates and Generating Dichotomous Outcomes * 
********************************************************************

* ethnicity
tab ethnicity3cat_25to1
recode ethnicity3cat_25to1 (99=2)
recode ethnicity3cat_25to1 (2=0)
label def ethnicity 0 "not Hispanic" 1 "Hispanic", replace
lab val ethnicity3cat_25to1 ethnicity 
tab ethnicity3cat_25to1  
   
* pain - dichotomized at moderate,severe,extreme or less than that
tab eq_pain_all, m
tab eq_pain_all, nol m

gen pain = eq_pain_all>=3 
replace pain = . if eq_pain_all==.
tab eq_pain_all pain, m

* severe ADL limitation - 0-3 vs 4 or more
tab adl_count, m

gen adl_severe = adl_count>=4 
replace adl_severe = . if adl_count==.
tab adl_count adl_severe, m

* curtailed life space - <60, vs 60+
sum compositelifespace, de

gen lifespace_lt60 = .
replace lifespace_lt60 = 1 if compositelifespace<60
replace lifespace_lt60 = 0 if compositelifespace>=60 & !missing(compositelifespace)

tab lifespace_lt60, m

* drain on financial resources - dichotomized at moderate,severe,extreme or less than that
tab ft_impact_health_all, m

gen ft_drain = ft_impact_health_all>=3 
tab ft_impact_health_all ft_drain

* EQ-5D-5L index - <0.5 vs 0.5-1.0
sum EQindex
gen eq5d5l_lt_point5 = .
replace eq5d5l_lt_point5 = 1 if EQindex<0.5
replace eq5d5l_lt_point5 = 0 if EQindex>=0.5 & !missing(EQindex)
tab eq5d5l_lt_point5
 
* covid recovery (back to how you felt in Jan 2020)
tab covid_recovery_all, m

gen covid_recovery_75plus = .
replace covid_recovery_75plus = 1 if covid_recovery_all>=75 & !missing(covid_recovery_all)
replace covid_recovery_75plus = 0 if covid_recovery_all<75
tab covid_recovery_75plus

gen covid_recovery_lt75 = .
replace covid_recovery_lt75 = 1 if covid_recovery_all<75 
replace covid_recovery_lt75 = 0 if covid_recovery_all>=75 & !missing(covid_recovery_all)
tab covid_recovery_lt75 
 
tab covid_recovery_75plus covid_recovery_lt75, m
 
* unemployed 
tab employ_all_ind, m
gen unemploy_all_ind = employ_all_ind==0
tab employ_all_ind unemploy_all_ind
tab unemploy_all_ind
 
**************************    
* Descriptive Statistics *  
**************************

* keep only those who are in the main analytic cohort (matched pairs in which 
* the comparators does NOT have a future infection)
keep if analytic_cohort==1
count //372, 186 matched pairs

* fill in weights for matchgroup comparators 
gsort matchgroupnumber -case 
list matchgroupnumber case total_weight in 1/25
bysort matchgroupnumber: replace total_weight = total_weight[_n-1] if total_weight==.
list matchgroupnumber case total_weight in 1/25

* descriptives 
svyset [pweight=total_weight]
svy: mean ageatindexdate_25to1, over(covid) 
svy: regress ageatindexdate_25to1 covid 
test covid

svy: mean bmi_25to1, over(covid) 
svy: regress bmi_25to1 covid 
test covid

svy: tab sex3cat_25to1 covid, col
svy: tab sex3cat_25to1 covid, count
table sex3cat_25to1 covid [pweight=total_weight]

svy: tab race3cat_25to1 covid, col
svy: tab race3cat_25to1 covid, count
table race3cat_25to1 covid [pweight=total_weight]

svy: tab ethnicity3cat_25to1 covid, col 
svy: tab ethnicity3cat_25to1 covid, count 
table ethnicity3cat_25to1 covid [pweight=total_weight]

svy: tab rurality2cat_25to1 covid, col 
svy: tab rurality2cat_25to1 covid, count 
table rurality2cat_25to1 covid [pweight=total_weight]

svy: tab smoking4cat_25to1 covid, col 
svy: tab smoking4cat_25to1 covid, count 
table smoking4cat_25to1 covid [pweight=total_weight]

svy: mean gagne_25to1, over(covid) 
svy: regress gagne_25to1 covid 
test covid

svy: mean bmi_25to1, over(covid) 
svy: regress bmi_25to1 covid 
test covid

svy: mean numipadmits_25to1, over(covid) 
svy: regress numipadmits_25to1 covid 
test covid

svy: mean util_numpcstops_25to1, over(covid) 
svy: regress util_numpcstops_25to1 covid 
test covid

svy: mean util_numscstops_25to1, over(covid) 
svy: regress util_numscstops_25to1 covid 
test covid

svy: mean util_nummhstops_25to1, over(covid) 
svy: regress util_nummhstops_25to1 covid 
test covid

svy: tab immuno_25to1 covid, col 
svy: tab immuno_25to1 covid, count 
table immuno_25to1 covid [pweight=total_weight]

svy: mean nosos_25to1, over(covid) 
svy: regress nosos_25to1 covid 
test covid

svy: mean canscore_25to1, over(covid) 
svy: regress canscore_25to1 covid 
test covid

svy: mean neareststa3ndistance_25to1, over(covid) 
svy: regress neareststa3ndistance_25to1 covid 
test covid

svy: tab pain covid, col 
svy: tab pain covid, count 
table pain covid [pweight=total_weight]

svy: tab adl_severe covid, col 
svy: tab adl_severe covid, count 
table adl_severe covid [pweight=total_weight]

svy: mean adl_count, over(covid)
svy: regress adl_count covid 
test covid

svy: tab lifespace_lt60 covid, col 
svy: tab lifespace_lt60 covid, count 
table lifespace_lt60 covid [pweight=total_weight]

svy: tab employ_all_ind covid, col 
svy: tab employ_all_ind covid, count 
table employ_all_ind covid [pweight=total_weight]

svy: tab unemploy_all_ind covid, col 
svy: tab unemploy_all_ind covid, count 
table unemploy_all_ind covid [pweight=total_weight]

svy: tab ft_drain covid, col 
svy: tab ft_drain covid, count 
table ft_drain covid [pweight=total_weight]

svy: tab ft_savings_all covid, col 
svy: tab ft_savings_all covid, count 
table ft_savings_all covid [pweight=total_weight]

svy: tab ft_necessities_all covid, col 
svy: tab ft_necessities_all covid, count 
table ft_necessities_all covid [pweight=total_weight]

svy: tab eq5d5l_lt_point5 covid, col 
svy: tab eq5d5l_lt_point5 covid, count 
table eq5d5l_lt_point5 covid [pweight=total_weight]

svy: mean EQindex, over(covid)
svy: regress EQindex covid 
test covid

svy: mean covid_recovery_all, over(covid)
svy: regress covid_recovery_all covid 
test covid

svy: tab covid_recovery_75plus covid, col 
svy: tab covid_recovery_75plus covid, count 
table covid_recovery_75plus covid [pweight=total_weight]

svy: mean fatigue_tscore, over(covid) 
svy: regress fatigue_tscore covid 
test covid

svy: mean compositelifespace, over(covid) 
svy: regress compositelifespace covid 
test covid

**********************************************************
* median days between survey completion within the pairs *
**********************************************************

* drop old surveydate
drop surveydate 

* create new surveydate
gen survey_stop_time_all = survey_stop_time 
replace survey_stop_time_all=survey_end_time_prox if survey_stop_time_all==""

gen double surveydatetime = clock(survey_stop_time_all, "YMDhms")
format surveydatetime %tc
gen surveydate = dofc(surveydatetime)
format surveydate %td

gsort matchgroupnumber -covid
by matchgroupnumber: gen surveydatediff = abs(surveydate-surveydate[_n-1])
sum surveydatediff, de

***********
* Figures *
***********

gen comparator = case==0
label def comparator 1 "Comparators" 0 "COVID-19 Survivors"
label var comparator comparator

label variable covid_recovery_all "COVID-19 Pandemic Recovery"
label variable adl_count "Health-related limitations of ADL/IADL"

*-----------------
* Unweighted 
*-----------------

* ADL & by Comparators

histogram adl_count, discrete freq  ///
    graphregion(color(white)) bfc(navy%90) blc(navy%5)  ///
    xtitle({bf:Health-related limitations in ADL/IADL}, size(small) margin(medium))  ///
    ytitle({bf:Frequency},size(small) margin(medium))  ///
    xlab(,labsize(small)) ylab(,labsize(small) angle(0))
    *graph save "Graph" "adl_fig1.gph", replace
    
histogram adl_count, discrete freq by(comparator, graphregion(color(white))) ///
    bfc(navy%90) blc(navy%5)  ///
    xtitle({bf:Health-related limitations in ADL/IADL}, size(small) margin(medium))  ///
    ytitle({bf:Frequency},size(small) margin(medium))  ///
    xlab(,labsize(small)) ylab(,labsize(small) angle(0))
    *graph save "Graph" "adl_fig2.gph", replace

twoway (histogram adl_count if covid==1, percent start(0) width(1)  ///
            graphregion(color(white)) color(navy%90)) ///
       (histogram adl_count if covid==0, percent start(0) width(1)  ///
            graphregion(color(white)) fcolor(none) lcolor(black)), ///
            xtitle(, margin(medium))   ytitle(,margin(medium))  ///    
            legend(label(1 "COVID-19 Survivors") label(2 "Comparators")) 
        *graph save "Graph" "adl_overlay.gph"    
            
* Pandemic recovery & by Comparators

histogram covid_recovery_all, discrete freq  ///
    graphregion(color(white)) bfc(navy%90) blc(navy%5)  ///
    xtitle({bf:COVID-19 Pandemic Recovery}, size(small) margin(medium))  ///
    ytitle({bf:Frequency},size(small) margin(medium))  ///
    xlab(,labsize(small)) ylab(,labsize(small) angle(0))
    *graph save "Graph" "covidrecovery_fig1.gph", replace

histogram covid_recovery_all, discrete freq by(comparator, graphregion(color(white)))  ///
    width(10) bfc(navy%90) blc(navy%5)  ///
    xtitle({bf:COVID-19 Pandemic Recovery}, size(small) margin(medium))  ///
    ytitle({bf:Frequency},size(small) margin(medium))  ///
    xlab(,labsize(small)) ylab(,labsize(small) angle(0))
    *graph save "Graph" "covidrecovery_fig2.gph", replace
 
twoway (histogram covid_recovery_all if covid==1, percent start(0) width(10) ///
            graphregion(color(white)) color(navy%90)) ///
       (histogram covid_recovery_all if covid==0, percent start(0) width(10) ///
            graphregion(color(white)) fcolor(none) lcolor(black)), ///
            xtitle(, margin(medium))   ytitle(,margin(medium))  ///    
            legend(label(1 "COVID-19 Survivors") label(2 "Comparators")) 
        *graph save "Graph" "covidrecovery_overlay.gph", replace            

*------------------------
* Weighted Histogram        
*------------------------
local k = 2
gen f_total_weight = round(10^`k'*total_weight, 1)

* ADL & by Comparators
twoway (histogram adl_count if covid==1 [fw=f_total_weight], percent start(0) width(1)  ///
            graphregion(color(white)) color(navy%90)) ///
       (histogram adl_count if covid==0 [fw=f_total_weight], percent start(0) width(1)  ///
            graphregion(color(white)) fcolor(none) lcolor(black)), ///
            xtitle("Health-related limitations of ADL/IADL", margin(medium))   ytitle(,margin(medium))  ///    
            legend(label(1 "COVID-19 Survivors") label(2 "Comparators")) 
       *graph save "Graph" "adl_overlay_weighted.gph"    
            
* Pandemic recovery & by Comparators
twoway (histogram covid_recovery_all if covid==1 [fw=f_total_weight], percent start(0) width(10) ///
            graphregion(color(white)) color(navy%90)) ///
       (histogram covid_recovery_all if covid==0 [fw=f_total_weight], percent start(0) width(10) ///
            graphregion(color(white)) fcolor(none) lcolor(black)), ///
            xtitle("COVID-19 Pandemic Recovery", margin(medium))   ytitle(,margin(medium))  ///    
            legend(label(1 "COVID-19 Survivors") label(2 "Comparators")) 
        *graph save "Graph" "covidrecovery_overlay_weighted.gph", replace            
      
        
*-----------------------
* Weighted Bar Chart
*-----------------------

label define covid 1 "COVID-19 Survivors" 0 "Comparators"
label val covid covid 

* ADL & by Comparators
graph bar (mean) adl_count [pweight = total_weight], over(covid)  ///
        graphregion(color(white)) ytitle("I/ADL Limitations (mean)")

* Pandemic recovery & by Comparators
graph bar (mean) covid_recovery_all [pweight = total_weight], over(covid)  ///
       graphregion(color(white)) ytitle("COVID-19 Pandemic Recovery (mean)")
 
*--------------------------------------------------------------
* Analysis of dichotomous variables, weighted & unweighted
*--------------------------------------------------------------

* weighted 
clogit pain covid ib2.race3cat_25to1 ethnicity3cat_25to1 [pweight = total_weight], group(matchgroupnumber) or
clogit adl_severe covid ib2.race3cat_25to1 ethnicity3cat_25to1 [pweight = total_weight], group(matchgroupnumber) or
clogit lifespace_lt60 covid ib2.race3cat_25to1 ethnicity3cat_25to1 [pweight = total_weight], group(matchgroupnumber) or
clogit unemploy_all_ind covid ib2.race3cat_25to1 ethnicity3cat_25to1 [pweight = total_weight], group(matchgroupnumber) or
clogit eq5d5l_lt_point5 covid ib2.race3cat_25to1 ethnicity3cat_25to1 [pweight = total_weight], group(matchgroupnumber) or
clogit covid_recovery_lt75 covid ib2.race3cat_25to1 ethnicity3cat_25to1 [pweight = total_weight], group(matchgroupnumber) or

* unweighted 
clogit pain covid ib2.race3cat_25to1 ethnicity3cat_25to1, group(matchgroupnumber) or
clogit adl_severe covid ib2.race3cat_25to1 ethnicity3cat_25to1, group(matchgroupnumber) or
clogit lifespace_lt60 covid ib2.race3cat_25to1 ethnicity3cat_25to1, group(matchgroupnumber) or
clogit unemploy_all_ind covid ib2.race3cat_25to1 ethnicity3cat_25to1, group(matchgroupnumber) or
clogit eq5d5l_lt_point5 covid ib2.race3cat_25to1 ethnicity3cat_25to1, group(matchgroupnumber) or
clogit covid_recovery_lt75 covid ib2.race3cat_25to1 ethnicity3cat_25to1, group(matchgroupnumber) or

*--------------------------------------
* analysis of continuous variables
*--------------------------------------
* reshape data to wide form for analysis of continuous variables
gsort matchgroupnumber -case
keep adl_count eq_pain_all fatigue_tscore employ_all_ind ///
			 compositelifespace ft_savings_all ft_necessities_all ///
			 ft_impact_health_all EQindex phq9_score covid_recovery_all ///
             race3cat_25to1 ethnicity3cat_25to1 ageatindexdate_25to1  			///
			 bmi_25to1 gagne_25to1 neareststa3ndistance_25to1 numipadmits_25to1 		///
			 util_numpcstops_25to1 util_nummhstops_25to1 		///
			 util_numscstops_25to1 matchgroupnumber case total_weight 

reshape wide adl_count eq_pain_all fatigue_tscore employ_all_ind ///
			 compositelifespace ft_savings_all ft_necessities_all ///
			 ft_impact_health_all EQindex phq9_score covid_recovery_all race3cat_25to1 ///
			 ethnicity3cat_25to1 ageatindexdate_25to1  			///
			 bmi_25to1 gagne_25to1 neareststa3ndistance_25to1 numipadmits_25to1 		///
			 util_numpcstops_25to1 util_nummhstops_25to1 		///
			 util_numscstops_25to1 total_weight, i(matchgroupnumber) j(case)
			 
order matchgroupnumber adl_count* fatigue_tscore* employ_all_ind* ///
			 compositelifespace* ft_savings_all* ft_necessities_all* ///
			 ft_impact_health_all* EQindex* phq9_score* covid_recovery* race3cat_25to1* ///
			 ethnicity3cat_25to1* ageatindexdate_25to1*  			///
			 bmi_25to1* gagne_25to1* neareststa3ndistance_25to1* numipadmits_25to1* 		///
			 util_numpcstops_25to1* util_nummhstops_25to1* 		///
			 util_numscstops_25to1*		 
order total_weight*, last 

drop total_weight0
rename total_weight1 total_weight
			 
* for continuous variables 
gen d_adl_count = adl_count1-adl_count0
gen d_fatigue_tscore = fatigue_tscore1 - fatigue_tscore0
gen d_compositelifespace = compositelifespace1 - compositelifespace0
gen d_ft_impact_health = ft_impact_health_all1 - ft_impact_health_all0
gen d_eqindex = EQindex1 - EQindex0 
gen d_phq9_score = phq9_score1-phq9_score0
gen d_covid_recovery = covid_recovery_all1-covid_recovery_all0

* combine missing with no for ethnicity 
tab ethnicity3cat_25to10 
tab ethnicity3cat_25to10, nol

recode ethnicity3cat_25to10 (99=2)
recode ethnicity3cat_25to10 (2=0)
label def ethnicity 0 "not Hispanic" 1 "Hispanic", replace
lab val ethnicity3cat_25to10 ethnicity 

recode ethnicity3cat_25to11 (99=2)
recode ethnicity3cat_25to11 (2=0)
lab val ethnicity3cat_25to11  ethnicity
tab ethnicity3cat_25to11

* weighted regressions
regress d_fatigue_tscore ib2.race3cat_25to11 i.ethnicity3cat_25to11 [pweight=total_weight] 
regress d_adl_count ib2.race3cat_25to11 i.ethnicity3cat_25to11 [pweight=total_weight]
regress d_compositelifespace ib2.race3cat_25to11 i.ethnicity3cat_25to11 [pweight=total_weight]
regress d_eqindex ib2.race3cat_25to11 i.ethnicity3cat_25to11 [pweight=total_weight]
regress d_covid_recovery ib2.race3cat_25to11 i.ethnicity3cat_25to11 [pweight=total_weight]

* unweighted regressions 
regress d_fatigue_tscore ib2.race3cat_25to11 i.ethnicity3cat_25to11 
regress d_adl_count ib2.race3cat_25to11 i.ethnicity3cat_25to11 
regress d_compositelifespace ib2.race3cat_25to11 i.ethnicity3cat_25to11 
regress d_eqindex ib2.race3cat_25to11 i.ethnicity3cat_25to11 
regress d_covid_recovery ib2.race3cat_25to11 i.ethnicity3cat_25to11 

* examine distribution
local k = 2
gen fwt = round(10^(`k')*total_weight,1)
	
* histogram with probability density 
histogram d_adl_count [fw=fwt], bin(25)
kdensity d_adl_count [fw=fwt]

histogram d_fatigue_tscore [fw=fwt], bin(25)
kdensity d_fatigue_tscore [fw=fwt]

histogram d_compositelifespace [fw=fwt], bin(25)
kdensity d_compositelifespace [fw=fwt]

histogram d_ft_impact_health [fw=fwt], bin(25)
kdensity d_ft_impact_health [fw=fwt]

histogram d_eqindex [fw=fwt], bin(25)
kdensity d_eqindex [fw=fwt]

log close
	