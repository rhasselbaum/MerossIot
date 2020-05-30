name: Build Test and Release

on:
  push:
    paths-ignore: [docs/**, README.md]
    branches: [ 0.4.X.X ]
  pull_request:
    branches: [ 0.4.X.X ]
jobs:
  # ----------------------------------
  # BUILD
  # ----------------------------------
  build:
    name: Build on Python ${{matrix.python_version}}
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python_version: ['3.7', '3.8']
    steps:
    # Checks-out your repository under $GITHUB_WORKSPACE, so your job can access it
    - uses: actions/checkout@v2
    - name: Setup Python ${{matrix.python_version}}
      uses: actions/setup-python@v2
      with:
        python-version: ${{matrix.python_version}}
    - name: Install python dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -U setuptools wheel
        if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
    - name: Build artifact
      run: python setup.py sdist bdist_wheel

  # -----------------------------------
  # Turn on ENV
  # -----------------------------------
  turn-on-env:
    name: Turn on test environment
    runs-on: ubuntu-latest
    env:
      TPLINK_USER: ${{ secrets.TPLINK_USER }}
      TPLINK_PASS: ${{ secrets.TPLINK_PASS }}
    steps:
      - name: Setup Node.js environment
        uses: actions/setup-node@v1.4.2
        with:
          node-version: 11.x
      - uses: actions/checkout@v2
      - name: Install npm dependencies
        run: |
          pushd ext-res/tests
          npm install 
          popd
      - name: Powering on the dev-environment
        run: |
          pushd ext-res/tests
          node ./switch.js --dev MEROSS_LAB --toggle=on
          echo "Waiting 60 seconds for the dev environment to become operative..."
          popd
      - name: Sleep for 45 seconds
        uses: jakejarvis/wait-action@master
        with:
          time: '45s'
        
  # ---------------------------------
  # Testing
  # ---------------------------------
  test:
    name: Testing
    runs-on: ubuntu-latest
    needs: [build, turn-on-env]
    steps:
    - uses: actions/checkout@v2
    - name: Setup Python ${{matrix.python_version}}
      uses: actions/setup-python@v2
      with:
        python-version: ${{matrix.python_version}}
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install pytest
        pip install pytest-cov
        if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
    - name: Test with pytest
      env:
        MEROSS_EMAIL: ${{ secrets.MEROSS_EMAIL }}
        MEROSS_PASSWORD: ${{ secrets.MEROSS_PASSWORD }}
      run: |
        pytest tests --doctest-modules --junitxml=junit/test-results.xml --cov=com --cov-report=xml --cov-report=html
    - name: Upload pytest test results
      uses: actions/upload-artifact@v1
      with:
        name: pytest-results
        path: junit/test-results.xml
      # Use always() to always run this step to publish test results when there are test failures
      if: ${{ always() }}
  
  # ------------------------------
  # Turn off ENV
  # ------------------------------
  turn-off-env:
    name: Turn off test environment
    runs-on: ubuntu-latest
    needs: [test]
    env:
      TPLINK_USER: ${{ secrets.TPLINK_USER }}
      TPLINK_PASS: ${{ secrets.TPLINK_PASS }}
    steps:
      - name: Setup Node.js environment
        uses: actions/setup-node@v1.4.2
        with:
          node-version: 11.x
      - uses: actions/checkout@v2
      - name: Install npm dependencies
        run: |
          pushd ext-res/tests
          npm install 
          popd
      - name: Powering on the dev-environment
        run: |
          pushd ext-res/tests
          node ./switch.js --dev MEROSS_LAB --toggle=off
          popd
    if: ${{ always() }}
    
  # -----------------------------
  # Build and Release
  # -----------------------------
  release:
    runs-on: ubuntu-latest
    needs: [test, build]
    steps:
      - name: Setup Python 3.8
        uses: actions/setup-python@v2
        with:
          python-version: 3.8
      - uses: actions/checkout@v2
      - name: Install python dependencies
        run: |
          python -m pip install --upgrade pip
          pip install -U setuptools wheel
          pip install twine
          if [ -f requirements.txt ]; then pip install -r requirements.txt; fi
      - name: Build artifact
        run: python setup.py sdist bdist_wheel --universal
      - name: Calculate Version
        id: tag
        run: |
          TAG=$(cat $GITHUB_WORKSPACE/.version)
          echo "Tag: $TAG"
          echo "::set-env name=tag::$TAG"
      - name: Release on GitHub
        uses: actions/create-release@v1
        env:
           GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
         tag_name: ${{env.tag}}
         release_name: Version ${{env.tag}}
      - name: Release on Pypi
        env:
          TWINE_USERNAME: ${{ secrets.TWINE_USERNAME }}
          TWINE_PASSWORD: ${{ secrets.TWINE_PASSWORD }}
        run: |
          twine upload -u "$TWINE_USERNAME" -p "$TWINE_PASSWORD" dist/*
