{-# LANGUAGE OverloadedStrings #-}

module Vote.Database ( Connection
                     , connectPostgreSQL
                     , electionByID
                     , candidatesForElection
                     , votesForCandidatesForElection
                     ) where

import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromRow
import Control.Applicative
import Control.Monad
import Data.Maybe
import Data.List
import Vote.Types

-- Data Types to match DB representation of votes
data VoteRow = VoteRow { voteRowID :: Int
                       , voteRowElectionID :: Int
                       } deriving (Show)

data PreferenceRow = PreferenceRow { preferenceRowCandidateID :: Int
                                   , preferenceRowValue :: Maybe Int
                                   } deriving (Show)

-- TypeClass instances to support reading out of DB
instance FromRow Election where
    fromRow = Election <$> field <*> field <*> field

instance FromRow Candidate where
    fromRow = Candidate <$> field <*> field

instance FromRow VoteRow where
    fromRow = VoteRow <$> field <*> field

instance FromRow PreferenceRow where
    fromRow = PreferenceRow <$> field <*> field

-- utility functions
voteRowsForElection :: Connection -> Election -> IO [VoteRow]
voteRowsForElection c e = query c "SELECT vote3fe_vote.* FROM vote3fe_vote WHERE vote3fe_vote.election_id = ?" (Only $ electionID e)

preferenceRowsForVoteRow :: Connection -> VoteRow -> IO [PreferenceRow]
preferenceRowsForVoteRow c v = query c "SELECT candidate_id, preference FROM vote3fe_preference WHERE vote_id = ?" (Only $ voteRowID v)

-- create a real vote from the database data
-- converts preferencerows into preferences, discarding preferences for candidates
-- that are not given.
-- That is, if you manage to insert a preference for candidate D, when only A B and C
-- are running, this will discard the preference for D.
voteFromRowsWithCandidates :: [Candidate] -> VoteRow -> [PreferenceRow] -> Vote
voteFromRowsWithCandidates cs v prs = 
  let vid = (voteRowID v)
      candidateIDs = map candidateID cs
      validPRs = filter (\pr -> (preferenceRowCandidateID pr) `elem` candidateIDs) prs
      ps = map (\pr -> Preference (fromJust $ find (\c -> candidateID c == preferenceRowCandidateID pr) cs)
                                  (preferenceRowValue pr))
               
               validPRs
  in Vote vid ps

-- public functions
electionByID :: Connection -> Int -> IO Election
electionByID c eid = let q = query c "SELECT * FROM vote3fe_election WHERE id = ?" (Only eid)
                      in liftM head q

candidatesForElection :: Connection -> Election -> IO [Candidate]
candidatesForElection c e = query c "SELECT vote3fe_candidate.* FROM vote3fe_ballotentry JOIN vote3fe_candidate ON vote3fe_ballotentry.candidate_id = vote3fe_candidate.id WHERE vote3fe_ballotentry.election_id = ?" (Only $ electionID e)

votesForCandidatesForElection :: Connection -> Election -> [Candidate] -> IO [Vote]
votesForCandidatesForElection conn election candidates = do
   voterows <- voteRowsForElection conn election
   prefrows <- mapM (preferenceRowsForVoteRow conn) voterows
   return $ zipWith (voteFromRowsWithCandidates candidates) voterows prefrows