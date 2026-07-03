---
name: "modelscope_skill"
description: "Fetches ModelScope Intel AI PC zone and OpenVINO related information including news, models, skills, articles, events and application notebooks. Invoke when users ask about ModelScope AI PC zone updates, OpenVINO, models, skills, technical articles or Intel AI tools."
---

# ModelScope AI PC Information Tool

This tool retrieves information from the ModelScope Intel AI PC zone and related Intel/OpenVINO resource websites using browser tools. It provides the latest updates on activities, models, skills, articles, events and OpenVINO application examples.

**Important Note:** The core value of this tool lies in providing **methods for acquiring information**, not static data. Web page content will be updated over time, so agents should follow the general methods below to dynamically obtain the latest information.

## Invocation Triggers

Call this skill when users ask:
- About "ModelScope AI PC" or "Intel AI PC" latest news
- About new models in the AI PC zone or OpenVINO-optimized models
- About SKILL updates, new skills or AI PC skill collection
- For technical articles in the AI PC zone
- For AI PC zone activities or competitions
- About OpenVINO, application notebooks, tutorials or Intel model hub

## General Information Retrieval Methods

Regardless of which page is accessed, follow the standard procedure below:

### Standard Operating Procedure

1. **Navigate to Target URL**
   - Use the `browser_navigate` tool to access the specified URL
   - URLs may change; if access fails, try the URL format without `www`

2. **Wait for Page Loading**
   - ModelScope pages are JavaScript-rendered Single Page Applications (SPA)
   - Must wait 2-3 seconds for content to fully load
   - Use the `browser_wait_for` tool to wait for a fixed duration

3. **Capture Page Snapshot**
   - Use the `browser_snapshot` tool to get the page structure
   - The snapshot contains all interactive elements and key content

4. **Extract Key Information**
   - Extract heading elements from the snapshot
   - Extract link names and references
   - Extract main text content
   - Pay attention to numbers (download counts, likes, etc.) and date information on the page

5. **Handle Dynamic Content**
   - If page content is incomplete, try scrolling the page (`browser_scroll`)
   - Click "View More" or similar buttons to load more content
   - Note that pages may have pagination or tab switching

6. **Format Output**
   - Organize extracted information by category
   - Include title, description, URL and related metadata
   - Present in clear Markdown format

## Information Sources and Detailed Extraction Methods

### 1. Latest News & Activity Updates

**URL:** https://modelscope.cn/brand/view/AI_PC

**Trigger Words:** "latest news", "activity updates", "AI PC latest", "announcements"

**Page Characteristics:**
- Navigation tabs at the top (About Us, OpenVINO Model Center, Claw Agent, AI Box, Local Deployment Guide, Blog Zone, Activity Overview, Discussion)
- Main content area contains headline news and important announcements
- Content displayed in card or list format

**Extraction Methods:**
- Identify all heading-type elements as news titles
- Extract link names as content summaries
- Pay attention to content with date tags
- Record alt text of related images as supplementary information

**Expected Content Types:**
- New model release announcements (e.g., Gemma4-12B, Qwen series, etc.)
- Platform feature updates (e.g., AI Box launch)
- Activity highlights and zone introduction

### 2. New Models

**URL:** https://modelscope.cn/brand/view/AI_PC?branch=2&tree=1

**Trigger Words:** "new models", "model updates", "model releases"

**Page Characteristics:**
- Displays a list of models related to the AI PC zone
- Each model may include name, description, preview image, release date
- May have metrics like download counts, likes, etc.

**Extraction Methods:**
- Extract model names and descriptions from link names
- Identify model-related numeric information (download counts, parameter counts, etc.)
- Record release date information
- Pay attention to model type tags (e.g., text-generation, image-captioning)

**Additional Model Sources:**

#### OpenVINO Official Organization Page
- **URL:** https://www.modelscope.cn/organization/OpenVINO
- **Purpose:** Official OpenVINO organization page on ModelScope, displaying all OpenVINO-optimized models
- **Extraction Method:** Extract model list, model names, descriptions and update times under the organization
- **Notes:** This page may load slowly or return empty content (0 refs appeared during testing). If first access fails, try waiting longer (5+ seconds) or refreshing the page; if still unable to get content, use Intel OpenVINO Model Hub as an alternative source

#### Intel OpenVINO Model Hub
- **URL:** https://www.intel.com/content/www/us/en/developer/tools/openvino-toolkit/model-hub.html
- **Purpose:** Official Intel OpenVINO Model Hub, providing models optimized for Intel hardware
- **Note:** This page is on Intel's official website with different structure than ModelScope, requiring special handling

### 3. SKILL Updates

**URL:** https://modelscope.cn/brand/view/AI_PC?branch=3&tree=2

**Trigger Words:** "SKILL", "skills", "skill updates", "new skills"

**Page Characteristics:**
- Displays a list of skills related to AI PC
- Each skill contains name, description, category tags, update date
- May have usage counts or download statistics

**Extraction Methods:**
- Extract link names as skill names and descriptions
- Identify category tags (e.g., Media Processing, Development Tools, Others)
- Record numeric information (download counts, usage counts)
- Pay attention to skill developer information

**Additional SKILL Sources:**

#### SKILL Collection Page
- **URL:** https://modelscope.cn/collections/Intel_AIPC/AIPC-Skills
- **Purpose:** AI PC Skills collection detail page, providing an overview of all available skills for Intel AI PC
- **Page Structure (Actual Test Results):**
  - Skills are displayed as links, with link names containing complete information: `Skill Name @Developer Downloads UsageCounts CategoryTags DeveloperInfo Version Description`
  - Example: `Party and Government Document Generation @NanjingHJLP 7.5k 851 Development Tools Developer: NanjingHJLP 01 02 03 /** * According to GB/T 9704-2012...`
  - Related models may be displayed at the bottom of the page (e.g., Qwen3, Qwen3.5, DeepSeek-V4, etc.)
- **Extraction Methods:** 
  - Parse link names, extract fields by splitting on spaces
  - Skill Name: portion before the "@" symbol in the link name
  - Developer: portion after "@" symbol and before the first number
  - Downloads: first number (may have k/M suffix)
  - Usage Counts: second number
  - Category Tags: Chinese tags after numbers (e.g., Development Tools, Media Processing, Others, Marketing)
  - Description: portion at the end of link name starting with `/** * `, containing detailed functional description of the skill
  - Pay attention to "View More" links on the page to load more skills
  - Record related model information (model name, version, author, update date)

### 4. Articles

**URL:** https://modelscope.cn/brand/view/AI_PC?branch=0&tree=5

**Trigger Words:** "articles", "tutorials", "technical articles", "blog", "blogs"

**Page Characteristics:**
- Displays technical articles and tutorials published in the AI PC zone
- Article list includes title, author, publication date, summary

**Extraction Methods:**
- Extract link names as article titles and summaries
- Identify author information (usually included in link names)
- Record publication dates
- Pay attention to article category tags

### 5. Event Details

**URL:** https://modelscope.cn/brand/view/AI_PC?branch=0&tree=6

**Trigger Words:** "events", "competitions", "hackathons"

**Page Characteristics:**
- Displays activities and competitions held in the AI PC zone
- Event information includes title, description, dates, deadlines, participation requirements, reward information

**Extraction Methods:**
- Extract event titles and descriptions
- Identify date and deadline information
- Record participation requirements and conditions
- Pay attention to rewards and prize information

### 6. OpenVINO Application Notebooks

**URL:** https://github.com/openvinotoolkit/openvino_notebooks

**Trigger Words:** "OpenVINO", "application notebooks", "notebooks", "tutorials", "examples"

**Page Characteristics:**
- GitHub repository page, different structure from ModelScope
- Contains README documentation, file directory, commit history
- Provides Jupyter Notebook format application examples

**Extraction Methods:**
- Extract directory structure and category information from README
- Identify Notebook filenames as example titles
- Record recent update dates and commit information
- Pay attention to Star and Fork counts of the repository
- Extract category directory names (e.g., computer-vision, nlp, model-optimization)

**Content Types:**
- Computer vision examples
- NLP model deployment
- Model optimization tutorials
- Intel hardware acceleration demos
- Jupyter Notebook examples

## Output Format Specification

After extracting information, output in the following format:

```markdown
## [Information Category]

### [Item Title]
- Description: [Brief description]
- URL: [Link to detail page]
- Category: [Category tags]
- Update Time: [Date information]
- Additional Info: [Download counts, usage counts and other numeric information]

---

### [Item Title 2]
...
```

## Example Workflow

**User Query:** "Tell me the latest news from ModelScope AI PC zone"

**Execution Steps:**
1. Use `browser_navigate` to navigate to https://modelscope.cn/brand/view/AI_PC
2. Use `browser_wait_for` to wait for 2 seconds
3. Use `browser_snapshot` to capture page snapshot
4. Extract all heading and link elements from the snapshot
5. Identify news titles and summary content
6. Output results in standard format

## Notes

- **Page Dynamics:** All web content will be updated over time. This tool provides methods for acquiring information, not static data
- **JavaScript Rendering:** ModelScope pages are SPAs. Must use browser tools, not simple HTTP GET requests
- **Wait Time:** Must wait 2-3 seconds after navigation for content to fully load
- **Page Structure Changes:** Page structures may change. Adjust extraction patterns based on actual snapshots
- **Multi-source Verification:** The same type of information may have multiple sources. Cross-verify to ensure information completeness
- **Cross-domain Differences:** GitHub and Intel official website have different page structures than ModelScope. Different extraction strategies are needed

## API Reference (Supplemental)

For programmatic access to ModelScope models, datasets and MCP services, use the following API:

**Base URL:** https://modelscope.cn/openapi/v1

**Authentication:** Bearer Token required

**Available Endpoints:**
- GET /users/me - Get current user information
- GET /models - Get model list (supports search and filter options)
- GET /models/{owner}/{repo_name} - Get specified model details
- GET /datasets - Get dataset list
- PUT /mcp/servers - Get MCP server list

**OpenAPI Documentation:** https://modelscope.cn/docs/openapi