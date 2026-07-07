/* =====================================================================================
   SWIFT CBPR+ Investigations (camt.110 / camt.111) - MS SQL Server 2019
   Flattened persistence schema for SR2026 Usage Guidelines:
     CCNR_CONR, OTHR, RQFI_COMP, RQFI_SANC, RQFI_UTEX, UTAP

   Design principles
   - One header table per message direction (Request / Response), holding the
     superset of flattened fields across ALL usage guidelines.
   - Repeating (unbounded) blocks are stored in narrow child tables.
   - Deeply nested, highly variable structures (booking confirmation, payment
     transaction status, transaction amendment / remittance) are persisted as
     JSON in NVARCHAR(MAX) columns so the schema stays simple while remaining
     queryable via JSON functions (ISJSON / JSON_VALUE / OPENJSON).
   - Every received raw message is also stored verbatim in dbo.MessageLog for
     full-fidelity replay and audit.
   ===================================================================================== */

/* ---------- Schema ------------------------------------------------------------------ */
IF SCHEMA_ID('swift') IS NULL
    EXEC('CREATE SCHEMA swift');
GO

/* ---------- Raw message log --------------------------------------------------------- */
IF OBJECT_ID('swift.MessageLog','U') IS NULL
CREATE TABLE swift.MessageLog
(
    MessageLogId    BIGINT         IDENTITY(1,1) NOT NULL,
    MessageName     NVARCHAR(20)   NOT NULL,          -- camt.110.001.01 / camt.111.001.02
    UsageGuideline  NVARCHAR(40)   NULL,              -- CCNR_CONR, OTHR, RQFI_COMP, ...
    SenderBIC       NVARCHAR(11)   NULL,              -- from SNL/FIH header if available
    ReceiverBIC     NVARCHAR(11)   NULL,
    RawXml          NVARCHAR(MAX)  NOT NULL,          -- verbatim payload
    ReceivedAt      DATETIME2(3)   NOT NULL CONSTRAINT DF_MessageLog_ReceivedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_MessageLog PRIMARY KEY (MessageLogId)
);
GO

/* ---------- camt.110 Investigation Request header (flattened) ------------------------ */
IF OBJECT_ID('swift.InvestigationRequest','U') IS NULL
CREATE TABLE swift.InvestigationRequest
(
    RequestId               BIGINT          IDENTITY(1,1) NOT NULL,
    MessageLogId            BIGINT          NOT NULL,

    -- InvestigationRequest2 / InvstgtnReq
    MsgId                   NVARCHAR(35)    NOT NULL,
    RqstrInvstgtnId         NVARCHAR(16)    NOT NULL,
    RspndrInvstgtnId        NVARCHAR(16)    NULL,
    EIR                     NVARCHAR(36)    NULL,         -- End-to-end investigation reference (UUID v4)

    -- ReqActn / InvestigationRequestAction1
    ReqActnCd               NVARCHAR(4)     NULL,         -- action code
    ActnRsnCd               NVARCHAR(4)     NULL,         -- action reason code
    ActnRsnAddtlInf1        NVARCHAR(105)   NULL,         -- up to 2 AddtlInf
    ActnRsnAddtlInf2        NVARCHAR(105)   NULL,

    -- Classification
    InvstgtnTp              NVARCHAR(4)     NOT NULL,      -- CCNR, CONR, OTHR, RQFI, UTAP ...
    InvstgtnSubTp           NVARCHAR(4)     NULL,          -- OTHR/RQFI sub-types (SANC/UTEX/COMP/...)
    SvcLvlCd                NVARCHAR(4)     NULL,          -- service level
    UndrlygInstrmCd         NVARCHAR(4)     NOT NULL,      -- underlying investigation instrument

    -- Undrlyg choice discriminator + flattened underlying data (superset)
    UndrlygChoice            NVARCHAR(10)   NOT NULL,      -- Initn / IntrBk / StmtNtry / Acct / Othr

    -- UnderlyingGroupInformation1 (shared by Initn / IntrBk)
    OrgnlMsgId              NVARCHAR(35)    NULL,
    OrgnlMsgNmId            NVARCHAR(35)    NULL,
    OrgnlCreDtTm            DATETIME2(3)    NULL,
    OrgnlMsgDlvryChanl      NVARCHAR(35)    NULL,

    -- UnderlyingPaymentTransaction7 (IntrBk)
    OrgnlInstrId            NVARCHAR(35)    NULL,
    OrgnlEndToEndId         NVARCHAR(35)    NULL,
    OrgnlTxId                NVARCHAR(35)    NULL,
    OrgnlUETR                NVARCHAR(36)    NULL,
    OrgnlIntrBkSttlmAmt     DECIMAL(18,5)   NULL,
    OrgnlIntrBkSttlmCcy      NCHAR(3)        NULL,
    OrgnlIntrBkSttlmDt       DATE            NULL,

    -- UnderlyingPaymentInstruction8 (Initn) - additional fields
    OrgnlPmtInfId           NVARCHAR(35)    NULL,
    OrgnlInstdAmt           DECIMAL(18,5)   NULL,
    OrgnlInstdAmtCcy        NCHAR(3)        NULL,
    ReqdExctnDt             DATE            NULL,
    ReqdColltnDt            DATE            NULL,

    -- UnderlyingStatementEntry5 (StmtNtry) - additional fields
    OrgnlStmtId             NVARCHAR(35)    NULL,
    OrgnlNtryRef            NVARCHAR(35)    NULL,
    OrgnlNtryAmt            DECIMAL(18,5)   NULL,
    OrgnlNtryAmtCcy         NCHAR(3)        NULL,
    OrgnlNtryValDt          DATE            NULL,
    OrgnlAcctIBAN           NVARCHAR(34)    NULL,
    OrgnlAcctOthrId         NVARCHAR(34)    NULL,
    OrgnlAcctCcy            NCHAR(3)        NULL,

    -- Underlying other / generic identification (Othr)
    UndrlygOthrId           NVARCHAR(35)    NULL,
    UndrlygOthrSchmeNm      NVARCHAR(35)    NULL,
    UndrlygOthrIssr         NVARCHAR(35)    NULL,

    -- Parties (always agents -> BICFI)
    RqstrBICFI              NVARCHAR(11)    NOT NULL,
    RspndrBICFI             NVARCHAR(11)    NOT NULL,
    ReqOrgtrBICFI           NVARCHAR(11)    NULL,

    CreatedAt               DATETIME2(3)    NOT NULL CONSTRAINT DF_InvReq_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_InvestigationRequest PRIMARY KEY (RequestId),
    CONSTRAINT FK_InvReq_MessageLog FOREIGN KEY (MessageLogId)
        REFERENCES swift.MessageLog (MessageLogId)
);
GO

CREATE INDEX IX_InvReq_MsgId           ON swift.InvestigationRequest (MsgId);
CREATE INDEX IX_InvReq_EIR             ON swift.InvestigationRequest (EIR);
CREATE INDEX IX_InvReq_RqstrInvstgtnId ON swift.InvestigationRequest (RqstrInvstgtnId);
CREATE INDEX IX_InvReq_InvstgtnTp      ON swift.InvestigationRequest (InvstgtnTp);
GO

/* ---------- camt.110 repeating investigation data (InvstgtnData, 1..n) --------------- */
IF OBJECT_ID('swift.InvestigationRequestData','U') IS NULL
CREATE TABLE swift.InvestigationRequestData
(
    RequestDataId   BIGINT        IDENTITY(1,1) NOT NULL,
    RequestId        BIGINT        NOT NULL,
    Seq              TINYINT       NULL,          -- CASE_Max3Number (1..999)
    RsnCd            NVARCHAR(4)   NOT NULL,        -- investigation reason code
    RsnSubTpCd       NVARCHAR(4)   NULL,           -- reason sub-type
    ReqNrrtv         NVARCHAR(500) NULL,           -- AdditionalRequestData / ReqNrrtv

    CONSTRAINT PK_InvestigationRequestData PRIMARY KEY (RequestDataId),
    CONSTRAINT FK_InvReqData_Request FOREIGN KEY (RequestId)
        REFERENCES swift.InvestigationRequest (RequestId) ON DELETE CASCADE
);
GO

CREATE INDEX IX_InvReqData_Request ON swift.InvestigationRequestData (RequestId);
GO

/* ---------- camt.111 Investigation Response header (flattened) ---------------------- */
IF OBJECT_ID('swift.InvestigationResponse','U') IS NULL
CREATE TABLE swift.InvestigationResponse
(
    ResponseId              BIGINT        IDENTITY(1,1) NOT NULL,
    MessageLogId            BIGINT        NOT NULL,

    -- InvestigationResponse9
    MsgId                   NVARCHAR(35)  NOT NULL,
    RspndrInvstgtnId        NVARCHAR(35)  NULL,          -- some UGs allow 35 chars

    -- InvestigationStatus2
    InvstgtnSts             NVARCHAR(4)   NOT NULL,       -- status code
    StsRsnCd                NVARCHAR(4)   NULL,
    StsRsnPrtry             NVARCHAR(35)  NULL,

    -- Original investigation request echo (InvestigationRequest3) - flattened
    OrgnlReqMsgId           NVARCHAR(35)  NOT NULL,
    OrgnlReqRqstrInvstgtnId NVARCHAR(16)  NOT NULL,
    OrgnlReqRspndrInvstgtnId NVARCHAR(16) NULL,
    OrgnlReqEIR             NVARCHAR(36)  NULL,
    OrgnlReqActnCd          NVARCHAR(4)   NULL,
    OrgnlReqActnRsnCd       NVARCHAR(4)   NULL,
    OrgnlReqInvstgtnTp      NVARCHAR(4)   NOT NULL,
    OrgnlReqInvstgtnSubTp   NVARCHAR(4)   NULL,
    OrgnlReqUndrlygInstrmCd NVARCHAR(4)   NOT NULL,
    OrgnlReqRqstrBICFI      NVARCHAR(11)  NOT NULL,
    OrgnlReqRspndrBICFI     NVARCHAR(11)  NOT NULL,

    CreatedAt               DATETIME2(3)  NOT NULL CONSTRAINT DF_InvRsp_CreatedAt DEFAULT SYSDATETIME(),

    CONSTRAINT PK_InvestigationResponse PRIMARY KEY (ResponseId),
    CONSTRAINT FK_InvRsp_MessageLog FOREIGN KEY (MessageLogId)
        REFERENCES swift.MessageLog (MessageLogId)
);
GO

CREATE INDEX IX_InvRsp_MsgId    ON swift.InvestigationResponse (MsgId);
CREATE INDEX IX_InvRsp_EIR      ON swift.InvestigationResponse (OrgnlReqEIR);
CREATE INDEX IX_InvRsp_Sts      ON swift.InvestigationResponse (InvstgtnSts);
GO

/* ---------- camt.111 repeating investigation data (InvstgtnData, 0..n) -------------- */
IF OBJECT_ID('swift.InvestigationResponseData','U') IS NULL
CREATE TABLE swift.InvestigationResponseData
(
    ResponseDataId           BIGINT          IDENTITY(1,1) NOT NULL,
    ResponseId               BIGINT          NOT NULL,

    OrgnlInvstgtnSeq         TINYINT         NULL,           -- sequence from original request
    OrgnlInvstgtnRsnCd       NVARCHAR(4)     NULL,
    OrgnlInvstgtnRsnSubTpCd  NVARCHAR(4)     NULL,

    -- RspnData discriminator: Conf / TxSts / TxData / RspnNrrtv
    RspnDataType             NVARCHAR(10)    NOT NULL,
    RspnNrrtv                NVARCHAR(500)  NULL,           -- narrative response

    -- Flattened booking confirmation (Conf / BookingConfirmation5)
    ConfAmt                  DECIMAL(18,5)   NULL,
    ConfAmtCcy               NCHAR(3)        NULL,
    ConfCdtDbtInd            NVARCHAR(4)     NULL,            -- CRDT / DBIT
    ConfXchgRate             DECIMAL(11,10)  NULL,
    ConfAcctIBAN             NVARCHAR(34)    NULL,
    ConfAcctOthrId           NVARCHAR(34)    NULL,
    ConfAcctCcy              NCHAR(3)        NULL,
    ConfBookgDt              DATE            NULL,
    ConfValDt                DATE            NULL,
    ConfRsn                  NVARCHAR(140)   NULL,
    -- Booking confirmation transaction references (TransactionReferences6)
    ConfTxMsgId              NVARCHAR(35)    NULL,
    ConfAcctSvcrRef          NVARCHAR(35)    NULL,
    ConfInstrId              NVARCHAR(35)    NULL,
    ConfEndToEndId           NVARCHAR(35)    NULL,
    ConfUETR                 NVARCHAR(36)    NULL,
    ConfTxId                 NVARCHAR(35)    NULL,
    ConfPrtryJson            NVARCHAR(MAX)   NULL,            -- proprietary refs (0..n) as JSON array

    -- Flattened payment transaction status (TxSts / PaymentTransactionStatus1)
    TxStsCd                  NVARCHAR(4)     NULL,
    TxStsRsnInfJson          NVARCHAR(MAX)   NULL,            -- StatusReasonInformation12 (0..n) as JSON

    -- Transaction amendment (TxData / TransactionAmendment1) - deep & variable -> JSON
    TxDataJson               NVARCHAR(MAX)   NULL,

    -- Response originator party (always agent -> BICFI)
    RspnOrgtrBICFI           NVARCHAR(11)    NULL,

    -- Related investigation location data (0..n) as JSON (InvestigationLocationData1)
    RltdInvstgtnId           NVARCHAR(35)    NULL,
    RltdLctnJson              NVARCHAR(MAX)   NULL,

    CONSTRAINT PK_InvestigationResponseData PRIMARY KEY (ResponseDataId),
    CONSTRAINT FK_InvRspData_Response FOREIGN KEY (ResponseId)
        REFERENCES swift.InvestigationResponse (ResponseId) ON DELETE CASCADE
);
GO

CREATE INDEX IX_InvRspData_Response ON swift.InvestigationResponseData (ResponseId);
GO

/* ---------- Helper view: one row per investigation case (request + latest response) -- */
IF OBJECT_ID('swift.InvestigationCaseView','V') IS NOT NULL DROP VIEW swift.InvestigationCaseView;
GO
CREATE VIEW swift.InvestigationCaseView AS
SELECT
    req.RequestId,
    req.MsgId                  AS RequestMsgId,
    req.EIR,
    req.InvstgtnTp,
    req.InvstgtnSubTp,
    req.RqstrInvstgtnId,
    req.RspndrInvstgtnId       AS ReqRspndrInvstgtnId,
    req.RqstrBICFI,
    req.RspndrBICFI,
    req.CreatedAt              AS RequestedAt,
    rsp.ResponseId,
    rsp.MsgId                  AS ResponseMsgId,
    rsp.InvstgtnSts,
    rsp.StsRsnCd,
    rsp.CreatedAt              AS RespondedAt
FROM swift.InvestigationRequest req
LEFT JOIN swift.InvestigationResponse rsp
       ON rsp.OrgnlReqEIR = req.EIR;
GO
