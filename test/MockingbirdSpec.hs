{-# OPTIONS_GHC -fno-warn-orphans #-}
module MockingbirdSpec (spec) where

import           Control.Concurrent
import           Data.Monoid
import qualified Data.Text               as T
import           Mockingbird
import           Test.Hspec
import           Test.QuickCheck
import           Web.Twitter.Types


spec :: Spec
spec = do
  parseSpec
  pprintSpec
  birdsSpec
  processAllSpec


parseSpec :: Spec
parseSpec = describe "parsing" $ do

  it "is left associative" $ do
    parseTweet "A B C"
      `shouldBe` Right (Var "A" :$ Var "B" :$ Var "C")

  it "respects parentheses" $ do
    parseTweet "A (B C)"
      `shouldBe` Right (Var "A" :$ (Var "B" :$ Var "C"))
    parseTweet "A ( B C )"
      `shouldBe` Right (Var "A" :$ (Var "B" :$ Var "C"))

  it "ignores extra spaces" $ do
    parseTweet "  A B C"
      `shouldBe` Right (Var "A" :$ Var "B" :$ Var "C")
    parseTweet "  A\n B C"
      `shouldBe` Right (Var "A" :$ Var "B" :$ Var "C")
    parseTweet "  A\n B C\n\n\t"
      `shouldBe` Right (Var "A" :$ Var "B" :$ Var "C")

  it "accepts identifiers with @s" $ do
    parseTweet "@A B C"
      `shouldBe` Right (Var "@A" :$ Var "B" :$ Var "C")

pprintSpec :: Spec
pprintSpec = describe "pprint" $ do

  it "does not use redundant spaces or parentheses" $ do
    pprint <$> parseTweet " A B C" `shouldBe` Right "A B C"

  it "is the right inverse of parseTweet" $ do
    property $ \e -> parseTweet (pprint e) `shouldBe` Right e

birdsSpec :: Spec
birdsSpec = describe "birds" $ do
  let test b v = eval <$> b <*> pure v
      parse bird tweet = do
        name <- nick <$> bird
        return $ parseTweet $ "@" <> name <> " " <> tweet

  context "K bird" $ do

    it "meets the definition" $ do
      Right v <- parse kBird "x y"
      test kBird v `shouldReturn` Var "x"

    it "doesn't eval when it is not the head" $ do
      let Right v = parseTweet "a b c"
      test kBird v `shouldReturn` v

    it "associates left" $ do
      Right v <- parse kBird "x y z"
      test kBird v `shouldReturn` (Var "x" :$ Var "z")

  context "S bird" $ do

    it "meets the definition" $ do
      Right v <- parse sBird "x y z"
      test sBird v `shouldReturn` Var "x" :$ Var "z" :$ (Var "y" :$ Var "z")

    it "associates left" $ do
      Right v <- parse sBird "x y z a"
      test sBird v `shouldReturn` Var "x" :$ Var "z" :$ (Var "y" :$ Var "z") :$ Var "a"

  context "I bird" $ do

    it "meets the definition" $ do
      Right v <- parse iBird "x"
      test iBird v `shouldReturn` Var "x"

    it "associates left" $ do
      Right v <- parse iBird "x y"
      test iBird v `shouldReturn` Var "x" :$ Var "y"

  context "M bird" $ do

    it "meets the definition" $ do
      Right v <- parse mBird "x"
      test mBird v `shouldReturn` (Var "x" :$ Var "x")

    it "associates left" $ do
      Right v <- parse mBird "x y"
      test mBird v `shouldReturn` Var "x" :$ Var "x" :$ Var "y"


processAllSpec :: Spec
processAllSpec = describe "processAll" $ do

  let testStatus t = Status { statusContributors = Nothing
                            , statusCoordinates = Nothing
                            , statusCreatedAt = error "time"
                            , statusCurrentUserRetweet = Nothing
                            , statusEntities = Nothing
                            , statusExtendedEntities = Nothing
                            , statusFavoriteCount = 0
                            , statusFavorited = Nothing
                            , statusFilterLevel = Nothing
                            , statusId = 1
                            , statusInReplyToScreenName = Nothing
                            , statusInReplyToStatusId = Nothing
                            , statusInReplyToUserId = Nothing
                            , statusLang = Nothing
                            , statusPlace = Nothing
                            , statusPossiblySensitive = Nothing
                            , statusScopes = Nothing
                            , statusQuotedStatusId = Nothing
                            , statusQuotedStatus = Nothing
                            , statusRetweetCount = 0
                            , statusRetweeted = Nothing
                            , statusRetweetedStatus = Nothing
                            , statusSource = ""
                            , statusText = t
                            , statusTruncated = False
                            , statusUser = error "here"
                            , statusWithheldCopyright = Nothing
                            , statusWithheldInCountries = Nothing
                            , statusWithheldScope = Nothing
                            }

  it "posts tweets when appropriate" $ do
    mvar <- newEmptyMVar
    bs <- iBird
    let cfg = testConfig [testStatus $ "@" <> nick bs <> " hi"]
                         (\bird tw -> case evalTweet bird tw of
                             Nothing -> return ()
                             Just t -> putMVar mvar (bird, t))
    processAll $ cfg { birds = [bs] }
    (bird, text) <- readMVar mvar
    nick bird `shouldBe` "tjmp_i"
    text `shouldBe` "hi"

  it "doesn't post tweets when not the first thing mentioned" $ do
    mvar <- newEmptyMVar
    bs <- iBird
    let cfg = testConfig [testStatus $ "hi @" <> nick bs]
                         (\bird tw -> case evalTweet bird tw of
                             Nothing -> return ()
                             Just t -> putMVar mvar (bird, t))
    processAll $ cfg { birds = [bs] }
    Nothing <- tryReadMVar mvar -- Can't use shouldReturn do to missing Eq instance
    return ()

  it "doesn't post tweets when evaluation loops" $ do
    mvar <- newEmptyMVar
    bs <- mBird
    let cfg = testConfig [testStatus $ "@" <> nick bs <> " @" <> nick bs]
                         (\bird tw -> case evalTweet bird tw of
                             Nothing -> return ()
                             Just t -> putMVar mvar (bird, t))
    processAll $ cfg { birds = [bs] }
    Nothing <- tryReadMVar mvar -- Can't use shouldReturn do to missing Eq instance
    return ()


instance Arbitrary (Exp T.Text) where
  arbitrary = fmap T.pack <$> arbitrary

instance Arbitrary (Exp String) where
  arbitrary = frequency [(3, var), (1, app)]
    where
      var = Var <$> listOf1 (elements ['-'..'a'])
      app = (:$) <$> arbitrary <*> arbitrary
