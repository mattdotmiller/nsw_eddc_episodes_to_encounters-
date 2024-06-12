# Grouping Episodes of Care into Patient Encounters for the New South Wales Emergency Department Data Collection (EDDC)

_Matthew Miller_

  

With advice from _Blanca Gallego, Louisa Jorm_ and Dami Sotade

  

The EDDC data used to prepare this code was supported by a NSW Institute of Trauma and Management (ITIM) Grant. For the details of that project, see: [https://osf.io/63qc7/](https://osf.io/63qc7/)

For the accompanying journal article that used this script see: [https://doi.org/10.1016/j.injury.2024.111570](https://doi.org/10.1016/j.injury.2024.111570)
  

Overview

  

The NSW emergency department data collection (EDDC) contains patient care episodes rather than admissions. For example, a patient can be seen in an emergency department, recorded as 'admitted' then subsequently transferred to another hospital via the emergency department, where they are also admitted. Therefore a single patient can be 'admitted' from two emergency department visits on the same day in a different hospital. Unfortunately, the documentation of a "mode of separation" is not always helpful. As a result; "Admitted: Transferred to another hospital" or "Departed: Transferred to another hospital w/out 1st being admitted to hospital transferred from" or "Departed: for other clinical service location" and "Admitted to Ward/inpatient unit" can refer to a similar process - that is being seen at one emergency department then transferred to another hospital (whether from the emergency department or ward". An admission needs to be created by combining the appropriate patient care episodes based on date as much as modes of separation.

  

Approach used here

  

Rather than using specific character fields describing modes of separation or transfers, the script below looks for overlapping episode periods and assumes that where an episode overlaps, it is part of the same encounter. Corrections are then applied .

  

This approach is consistent with the naming conventions outlined in [Vallmuur K, McCreanor V, Cameron C, et al. Inj Prev 2021;27:479–489](https://injuryprevention.bmj.com/content/27/5/479) where an _Episode_ is the discrete unit of activity for a patient, and also referred to as a separation. Episdes/separations may include discharge, transfer or death, or ‘statistical’ separations such as episode type changes. An _Encounter_ is made up of contiguous episodes of care. This can include episodes between health services so long as they are related temporally. Episodes usually have no more than 24–48 hours between them (in other words, depending on the data you can allow 24-48 hours between episodes and include them in the same encounter.

  

**Step 1.** Convert the SAS files to R

  

*   replace numeric codes with text from data dictionaries
*   make sure times are posixct format
*   relabel columns to something more readable
*   remove duplicate entries

  

**Step 2.** create\_ed\_episodes function

  

This function takes each PPN and creates the encounters

  

*   create a column for the end of the episode, currently set at 12 hours.
*   create a column that displays the time interval between an episode and the previous episode, in hours (called incriment\_int)
*   create a column that returns whether an episode period overlaps with the episode period of another episode
*   create a second column that returns the smallest row number of the overlap of episode periods. This is used to join up the overlapping episodes later
*   create a "same as next column" that returns yes or no according to whether the episodes are recorded as overlapping with each other, if there are less than 24-hours between episodes where a patient was recorded as being transferred
*   create a column that increments the encounter-episodes based on whether the next episode is the same as the previous (no increment) or not. In the script this is inverted.
*   after encounters are created, adjust them for episodes that overlap but are not contiguous (eg an inpatient episode that is 3-4 rows away)
*   correct encounter number so they are sequential
*   create encounter periods, episode numbers per encounter, and a unique encounter id (enctr\_id) that can be used for grouped transformations later.

  

These steps are performed for each individual PPN which is added to a list. This is then reduced to a dataframe

  

**Step 3.** Run the function

  

This is the code the runs the function. It offers the ability to run it in "chunks" of PPNs so that it can be split across R sessions if needed to speed up the processing. For example, if it is broken into 500 chucks, 1 to 100 can be run on one R session and 101 to 200 on another as so on. These can be joined later (the script to do this is not provided as it depends on where the dataframes are saved). Otherwise, all of the PPNs can be run in 500 or 1000 groups of PPNs to help save memory.

  

This script can take a long time to execute. For a EDDC file of 3 million patients(PPNs) it took approximately 4 days to run on an HP intel computer with 32GB of memory.

  

The new fields are:

| Variable | Notes |
| ---| --- |
| episode\_pd\_end | created from arrival\_dtg + 12 hours |
| episode\_pd | arrival\_dtg %--% episode end dtg |
| enctr | encounter number per PPN |
| enctr\_episode | consecutive episode number as part of each encounter |
| eddc\_enctr\_id | unique code for each encountr |
| enctr\_start\_date | earliest episode start DTG in an encunter |
| enctr\_disch\_date | latest episode end DTG in an encounter |
| enctr\_pd | admsn\_date %--% disch\_date |
| max\_episodes | maximum number of episodes in each encounter |
