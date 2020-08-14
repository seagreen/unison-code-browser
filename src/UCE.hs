module UCE where

import Concur.Replica (Attr (..), Attrs, HTML, VDOM (..), clientDriver)
import qualified Concur.Replica.Run
import qualified Data.Map.Strict as Map
import Data.Text.Encoding (decodeUtf8)
import qualified Network.Wai as Wai
import qualified Network.Wai.Middleware.Static as Static
import Network.WebSockets (defaultConnectionOptions)
import qualified UCE.Code
import UCE.Prelude
import qualified UCE.UI

run :: Int -> String -> IO ()
run port projectDirectory = do
  codeinfo <- UCE.Code.load projectDirectory
  Concur.Replica.Run.run
    port
    index
    defaultConnectionOptions
    static
    (\_ -> UCE.UI.app codeinfo UCE.UI.Searching)

static :: Wai.Middleware
static =
  Static.staticPolicy $
    Static.only [("custom.css", "custom.css"), ("bulmaswatch.min.css", "bulmaswatch.min.css")]

index :: HTML
index =
  [ VLeaf "!doctype" (fl [("html", ABool True)]) Nothing,
    VNode
      "html"
      mempty
      Nothing
      [ VNode
          "head"
          mempty
          Nothing
          [ VLeaf "meta" (fl [("charset", AText "utf-8")]) Nothing,
            VNode "title" mempty Nothing [VText "Unison Code Explorer"],
            VLeaf
              "meta"
              ( fl
                  [ ("name", AText "viewport"),
                    ("content", AText "width=device-width, initial-scale=1")
                  ]
              )
              Nothing,
            VLeaf
              "link"
              ( fl
                  [ ("href", AText "./bulmaswatch.min.css"),
                    ("rel", AText "stylesheet")
                  ]
              )
              Nothing,
            VLeaf
              "link"
              ( fl
                  [ ("href", AText "custom.css"),
                    ("rel", AText "stylesheet")
                  ]
              )
              Nothing
          ],
        VNode
          "body"
          mempty
          Nothing
          [ VNode
              "script"
              (fl [("language", AText "javascript")])
              Nothing
              [VRawText $ decodeUtf8 clientDriver]
          ]
      ]
  ]
  where
    fl :: [(Text, Attr)] -> Attrs
    fl = Map.fromList
