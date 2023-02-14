#import libraries - I use pacman to load libraries as it keeps them uptodate and installs any library I am missing
#if you dont have pacman you will need to run install.packages("pacman")
library(pacman)
p_load(tidyverse, checkmate, stringr, lubridate, gdata, readxl, gmodels, naniar, openxlsx, ggpubr, janitor, skimr, REDCapR, hablar, mefa)
p_load(haven, rebus)


# Step 1 convert SAS files ------------------------------------------------
# Read in the SAS data
#this assumes all the files are in your working directory

eddc_sensitive <- read_csv("eddc_sensitive.csv") %>%
  clean_names()

eddc_formats <- read_csv("eddc_formats.csv")

#sort out dates
eddc_sensitive <- eddc_sensitive %>%
  mutate(arrival_dtg = dmy_hms(str_c(arrival_date, arrival_time, sep = " ")))


#the following converts the codes to text
recode_referral <- eddc_formats %>%
  filter(DomainItemName == "Referral Source - ED") %>%
  select(DomainValueCode, DomainValueDescriptiveTerm)

recode_arrival <- eddc_formats %>%
  filter(DomainItemName == "Mode of Arrival") %>%
  select(DomainValueCode, DomainValueDescriptiveTerm)


recode_separation <- eddc_formats %>%
  filter(DomainItemName == "Mode of Separation (ED)") %>%
  select(DomainValueCode, DomainValueDescriptiveTerm)

recode_triage <- eddc_formats %>%
  filter(DomainItemName == "Triage Category") %>%
  select(DomainValueCode, DomainValueDescriptiveTerm)

recode_facid <- read_csv("apdc_fac_ident.csv")%>% #this comes with the APDC data, is a list of NSW health facilities and codes
  select(coded = start, chr_label = label)

recode_areaid <- eddc_formats %>%
  filter(DomainItemName == "Area Identifier") %>%
  select(DomainValueCode, DomainValueDescriptiveTerm)

recode_fac_type <- eddc_formats %>%
  filter(DomainItemName == "Facility Type") %>%
  select(DomainValueCode, DomainValueDescriptiveTerm)




eddc <- eddc_sensitive %>%
  mutate(referral_source_chr = recode_referral$DomainValueDescriptiveTerm[match(as.character(eddc_sensitive$ed_source_of_referral), as.character(recode_referral$DomainValueCode))],
         mode_of_arrival_chr = recode_arrival$DomainValueDescriptiveTerm[match(as.character(eddc_sensitive$mode_of_arrival), as.character(recode_arrival$DomainValueCode))],
         mode_of_separation_chr = recode_separation$DomainValueDescriptiveTerm[match(as.character(eddc_sensitive$mode_of_separation), as.character(recode_separation$DomainValueCode))],
         triage_chr = recode_triage$DomainValueDescriptiveTerm[match(as.character(eddc_sensitive$triage_category), as.character(recode_triage$DomainValueCode))],
         facility_identifier_chr = recode_facid$chr_label[match(as.character(eddc_sensitive$facility_identifier), as.character(recode_facid$coded))],
         area_identifier_chr = recode_areaid$DomainValueDescriptiveTerm[match(as.character(eddc_sensitive$area_identifier), as.character(recode_areaid$DomainValueCode))],
         facility_type_chr = recode_fac_type$DomainValueDescriptiveTerm[match(as.character(eddc_sensitive$facility_type), as.character(recode_fac_type$DomainValueCode))])

rm(recode_referral,recode_arrival,recode_separation,recode_triage,recode_facid,recode_areaid, recode_fac_type, eddc_formats, apdc_fac_ident, eddc_sensitive)

eddc <- distinct(eddc, ppn, arrival_dtg, .keep_all = TRUE) # duplicates removed

eddc <- eddc %>%
  convert(chr(ed_diagnosis_code, ed_diagnosis_code_sct))






# create ED periods which accounts for patients transferred between EDs
#this isn't used, but is a helpful list of some modes of separation
end_eddc_pd = c("Admitted & discharged as inpatient within ED", 
                "Admitted: Left at own risk", 
                "Admitted to Ward/inpatient unit, not a Critical Care Ward",
                "Admitted: Died in ED",
                "Admitted: To Critical Care Ward (including ICU1/ICU2/CCU/COU/NICU)",
                "Admitted: Via Operating Suite",
                "Dead on Arrival",
                "Departed: Did not wait",
                "Departed: Left at own risk",
                "Departed: Treatment completed")

#this arranges ED epsodes into arrival periods so that where a patient is transferred between EDs then it is counted as part of the 
#same episode. Three new variables, ed_enctr (number of ed visits, and ed_arrive_pd combines the arrival periods. 


# Step 2: the create ED episodes function ---------------------------------


create_ed_episodes <- function(x) {
  
  time_stamp_1 <- now()
  group_length <- max(cycle_ppns)
  
  ppn1 <- out[[x]]

  
  print(str_c("processing group", x, "of", chunk_no, "at", now(), sep=" "))
  
  
  create_ed_encounter_single_ppn <- function(y) {
    

    
    #write a message regarding progress
    ppn_single <- y
    total_ppn <- length(ppn1)
    loctn_of_ppn <- which(ppn_single == ppn1)
    percent_complete_full = (loctn_of_ppn / total_ppn)*100
    percent_complete = round(percent_complete_full, digits=3)
    #writeLines(str_c("processing ppn",loctn_of_ppn, "of",total_ppn, "from group",x , "at", now(), sep=" "))
    #writeLines(str_c(percent_complete, "% complete", sep=" "))
    time_stamp_1 <- now()
    
    #process the ppns
    
    
    
    
    eddc_enctrs <- eddc %>%
      filter(ppn == ppn_single) %>%
      select(ppn, project_recnum, arrival_dtg, mode_of_separation_chr, facility_identifier_chr) %>%
      #select(ppn, project_recnum, arrival_dtg, mode_of_separation_chr, facility_identifier_chr) %>%
      arrange(desc(arrival_dtg),  .by_group = TRUE) %>%
      mutate(episode_pd_end = arrival_dtg + hours(12)) %>%
      mutate(episode_pd = arrival_dtg %--% (arrival_dtg + hours(12))) %>%
      mutate(incriment_int = abs(as.numeric(difftime(arrival_dtg, lag(arrival_dtg)), units="hours")))%>%
      mutate(overlaps = map_lgl(seq_along(episode_pd), function(x){
        #Get all Int indexes other than the current one
        y = setdiff(seq_along(episode_pd), x)
        #The interval overlaps with all other intervals
        #return(all(int_overlaps(Int[x], Int[y])))
        #The interval overlaps with any other intervals
        return(any(int_overlaps(episode_pd[x], episode_pd[y])))
      }))%>%
      mutate(overlaps_with = map(seq_along(episode_pd), function(x){
        #Get all Int indexes other than the current one
        y = (seq_along(episode_pd))
        #The interval overlaps with all other intervals
        #return(all(int_overlaps(Int[x], Int[y])))
        #The interval overlaps with any other intervals
        return(which(int_overlaps(episode_pd[x], episode_pd[y])))
      }))%>%
      unnest(overlaps_with) %>%
      group_by(arrival_dtg) %>%
      slice_min(overlaps_with) %>%
      ungroup() %>%
      arrange(desc(arrival_dtg)) %>%
      mutate(item_no = row_number()) %>%
      mutate(lag_dist = item_no - overlaps_with)%>%
      mutate(same_as_next = case_when(
        overlaps_with == lag(item_no) ~ "yes",
        lead(mode_of_separation_chr) ==  "Admitted: Transferred to another hospital" & incriment_int <24 & lead(facility_identifier_chr) != facility_identifier_chr ~ "yes",
        lead(mode_of_separation_chr) ==  "Departed: Transferred to another hospital w/out 1st being admitted to hospital transferred from"  & incriment_int <24 & lead(facility_identifier_chr) != facility_identifier_chr ~ "yes",
        lead(mode_of_separation_chr) ==  "Departed: for other clinical service location"  & incriment_int <24 & lead(facility_identifier_chr) != facility_identifier_chr ~ "yes",
        TRUE ~ "no")) %>%
      mutate(incriment = case_when(
        same_as_next == "yes" ~ 0,
        same_as_next == "no" ~ 1))%>%
      mutate(cum_inc = cumsum(incriment),
             enctr = (sum(incriment)+1) - (cum_inc)) %>%
      mutate(enctr = case_when(
        is.na(enctr) & incriment == 1 ~lag(enctr)+1,
        is.na(enctr) & incriment == 0 ~ lag(enctr),
        TRUE ~ enctr))
    
    # the following loop runs the correction below the same number of times as their are rows. 
    # This allows multiple checks of the correction to the admission
    
    for (i in 1:nrow(eddc_enctrs)) { 
      
      
      eddc_enctrs <- eddc_enctrs %>%
        mutate(enctr = map_dbl(seq_along(enctr), function(x){ #go along each row
          if (lag_dist[x] >=1) { #if there is an overlap with an item
            
            z <- overlaps_with[x] #record the item it overlaps with
            
            y <- eddc_enctrs[[z,"enctr"]] # record the admisson of the overlapped item
            
            eddc_enctrs[x,"enctr"] <- y #assign that admission to this row
            
          } else { 
            
            
            enctr[x] <- enctr[x] #if no overlap then the admisson remains the same 
            
          }
        }))
    }
    
    
    eddc_enctrs <- eddc_enctrs %>%
      arrange(enctr) %>% 
      mutate(enctr = as.numeric(factor(enctr))) %>%
      group_by(enctr) %>%
      mutate(enctr_episode = as.numeric(factor(arrival_dtg)))%>%
      mutate(enctr_episode = if_else(is.na(enctr_episode), 1, enctr_episode, 1)) %>% #this corrects of the rare occasion that the above returns an NA
      mutate(max_episodes = max(enctr_episode)) %>%
      mutate(eddc_enctr_id = str_c(ppn, as.character(max_episodes),as.character(enctr) )) %>%
      #this final section creates time periods, admit and discharge dates
      mutate(enctr_start_date = min(arrival_dtg),
             enctr_disch_date = max(episode_pd_end)) %>%
      mutate(enctr_pd = enctr_start_date %--% enctr_disch_date) %>% # the period is the first arrival date and then 12 hours past the last arrival date
      ungroup() %>%
      select(project_recnum, ppn, episode_pd_end, episode_pd, enctr_start_date, enctr_disch_date,enctr_pd, enctr, enctr_episode, max_episodes, eddc_enctr_id)
    
    
  }
  
  eddc_enctr_single <- map(ppn1, create_ed_encounter_single_ppn) 
  
  
  print(str_c("Now reducing the lists of ppns to a dataframe"))
  
  
  eddc_enctrs_completed <- reduce(eddc_enctr_single, rbind.data.frame) 
  
  time_stamp_2 <- now()
  time_to_process <- difftime(time_stamp_2, time_stamp_1, units = "hours")
  time_to_complete <- as.numeric(time_to_process * (group_length - x))
  time_to_complete <- round(time_to_complete, digits = 2)
  
  print(str_c("Completed group " , x , " Estimated completion time ", time_to_complete, " hours"))
  
  eddc_adsmsn_list <<- eddc_enctrs_completed
  
}


# Step 3: run the function (including in chunks) ----------------------------------


ppns <- as.vector(unique(eddc$ppn))

# specify the chunk number as 100
chunk_no=500

# split the vector by chunk number by specifying 
# labels as FALSE
out <- split(ppns, cut(seq_along(ppns),chunk_no,labels = FALSE))

cycle_ppns <- 1:500

eddc_adsmsn_list <- map(cycle_ppns, create_ed_episodes)

eddc_adsmsn <-reduce(eddc_adsmsn_list, rbind.data.frame)

rm(eddc_adsmsn_list) # free up some memory

eddc <- eddc %>%
  left_join(eddc_adsmsn, by = c("ppn", "project_recnum")) %>%
  relocate(project_recnum, ppn, age_recode, clinical_codeset, ed_source_of_referral, ed_diagnosis_code,ed_diagnosis_code_sct,ed_visit_type,
           referral_source_chr, mode_of_arrival_chr, mode_of_separation_chr, triage_chr, facility_identifier_chr, area_identifier_chr,
           facility_type_chr, ed_diagnosis_code_updated, text_dx, arrival_dtg, episode_pd_end, episode_pd, enctr_start_date, enctr_disch_date,enctr_pd, enctr, enctr_episode, max_episodes, eddc_enctr_id)

#ed_diagnosis_code_updated, text_dx need to be removed for the github version


saveRDS(eddc, file = (eddc.RDS"))
